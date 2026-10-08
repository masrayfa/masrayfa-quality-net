# frozen_string_literal: true

module Portfolios
  # N10: Generates a structured skill portfolio from the full transcript
  # and final coverage map using Gemini Pro.
  # Runs post-session as a background job.
  class Generator
    def initialize(session:, gemini_client: nil)
      @session = session
      @gemini_client = gemini_client || Gemini::HttpClient.new(
        model:   ENV.fetch('GEMINI_PRO_MODEL', 'gemini-2.0-pro-001'),
        timeout: 180  # up to 3 minutes for large transcripts
      )
    end

    # Returns the Portfolio record with skills populated.
    def call
      portfolio = @session.portfolio || @session.create_portfolio!(
        candidate_id:      @session.candidate_id,
        generation_status: 'pending'
      )

      portfolio.update!(generation_status: 'generating')

      prompt   = build_prompt
      response = @gemini_client.generate_content(prompt, temperature: 0.2)

      save_skills(portfolio, response)
      portfolio.update!(generation_status: 'complete', generated_at: Time.current)

      Rails.logger.info("[N10] Portfolio generated for session #{@session.id}")
      portfolio
    rescue => e
      portfolio&.update!(generation_status: 'failed', generation_error: e.message)
      Rails.logger.error("[N10] Portfolio generation failed for session #{@session.id}: #{e.class} #{e.message}")
      raise
    end

    private

    def build_prompt
      assessment       = @session.assessment
      configured_skills = assessment.assessment_skills.order(:display_order)
      coverage_maps     = @session.coverage_maps.order(:id)
      turns             = @session.transcript_turns.ordered

      skills_text = configured_skills.map { |s| skill_definition_block(s) }.join("\n\n")

      coverage_json = {
        skills:     coverage_maps.reject(&:is_discovered).map { |m| coverage_json(m) },
        discovered: coverage_maps.select(&:is_discovered).map { |m| coverage_json(m) }
      }.to_json

      transcript_text = turns.map { |t| "[#{t.speaker.upcase}]: #{t.text}" }.join("\n")

      <<~PROMPT
        You are evaluating a completed skills assessment interview to produce a structured skill portfolio.

        ROLE BEING ASSESSED: #{assessment.name}

        SKILL DEFINITIONS AND BEHAVIORAL ANCHORS:
        #{skills_text}

        UNIVERSAL L1-L5 ANCHORS (use for discovered skills):
        L1 — Executes with explicit guidance and close review. Understands conceptually but cannot apply independently.
        L2 — Executes independently on routine scope. Uses known patterns. Handles common cases but not edge cases.
        L3 — Executes complex, ambiguous scope. Makes tradeoffs. Handles edge cases. Can teach L1-L2.
        L4 — Defines standards and creates reusable systems. Resolves systemic problems. Cross-team impact.
        L5 — Org-level authority. Shapes how the skill is practiced. Rare.

        FINAL COVERAGE MAP:
        #{coverage_json}

        FULL INTERVIEW TRANSCRIPT:
        #{transcript_text}

        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        TASK
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        For EACH skill in the coverage map (both configured and discovered):

        1. FIND THE EVIDENCE
           Read all transcript turns where this skill was discussed.
           Identify the 2-3 most revealing quotes from the CANDIDATE (not the AI).
           A quote is revealing if it shows HOW they think, not just WHAT they know.

        2. ASSIGN A LEVEL
           Compare the candidate's actual behavior to the L1-L5 anchors.
           Assign the highest level where you see CONSISTENT evidence, not just one strong moment.
           If evidence is mixed (mostly L2 with one L3 moment), assign L2.

        3. WRITE THE COMPETENCY SUMMARY
           2-3 sentences. Focus on patterns, not individual answers.
           What does this person reliably do at this skill? What's the ceiling? What's missing?

        4. ASSIGN CONFIDENCE
           high — probe_count >= 3 AND state = covered
           medium — probe_count = 2 OR state = partial
           low — probe_count <= 1 OR state = initiated

        OUTPUT (JSON only, no prose):
        {
          "configured_skills": [
            {
              "skill_id": "sk-eng-001",
              "skill_label": "React / Frontend Development",
              "level": 3,
              "confidence": "high",
              "evidence": ["quote 1", "quote 2", "quote 3"],
              "competency_summary": "2-3 sentence summary"
            }
          ],
          "discovered_skills": [
            {
              "skill_label": "Micro-frontend Architecture",
              "level": 2,
              "confidence": "low",
              "evidence": ["quote 1"],
              "competency_summary": "2-3 sentence summary"
            }
          ]
        }
      PROMPT
    end

    def skill_definition_block(skill)
      lines = ["━━━━━━━━━━━━━━━"]
      lines << "SKILL: #{skill.skill_label} (#{skill.skill_id || 'custom'})"
      lines << "SCOPE: #{skill.scope_include}" if skill.scope_include.present?
      lines << ""
      lines << "L1 — #{skill.l1_anchor}"
      lines << "L2 — #{skill.l2_anchor}"
      lines << "L3 — #{skill.l3_anchor}"
      lines << "L4 — #{skill.l4_anchor}"
      lines << "L5 — #{skill.l5_anchor}"
      lines.join("\n")
    end

    def coverage_json(map)
      {
        id:          map.skill_id || map.skill_label.downcase.gsub(/\s+/, '-'),
        label:       map.skill_label,
        state:       map.state,
        probe_count: map.probe_count,
        is_discovered: map.is_discovered
      }
    end

    def save_skills(portfolio, response)
      data = response.is_a?(Hash) ? response : JSON.parse(response)
      @coverage_maps = @session.coverage_maps.to_a

      # B2: all-or-nothing. A malformed later skill must not leave earlier
      # rows behind on a portfolio that ends up failed. requires_new: true so
      # the unit gets a SAVEPOINT (and honest rollback) even when an outer
      # transaction already exists (e.g. the specs' DatabaseCleaner wrapper).
      portfolio.transaction(requires_new: true) do
        # Destroy existing skills (idempotent regeneration)
        portfolio.portfolio_skills.destroy_all

        (data['configured_skills'] || []).each do |skill_data|
          persist_skill!(portfolio, skill_data, discovered: false)
        end

        (data['discovered_skills'] || []).each do |skill_data|
          persist_skill!(portfolio, skill_data, discovered: true)
        end
      end
    end

    # ENF-1: confidence is capped by the session's coverage evidence
    # (PRD-01 §5). The LLM may claim at most what coverage supports; the
    # server never persists a stronger claim (and never upgrades one).
    CONFIDENCE_RANK = { 'low' => 0, 'medium' => 1, 'high' => 2 }.freeze

    def enforce_confidence(skill_data, claimed, discovered:)
      allowed = allowed_confidence(coverage_map_for(skill_data, discovered:))
      return claimed if CONFIDENCE_RANK[claimed] <= CONFIDENCE_RANK[allowed]

      Rails.logger.warn(
        "[N10] confidence #{claimed.inspect} capped to #{allowed.inspect} for " \
        "#{skill_data['skill_label'].inspect}: coverage does not support the claim"
      )
      allowed
    end

    # high   — probe_count >= 3 AND state covered
    # medium — probe_count == 2 OR state partial
    # low    — everything else (including no coverage map at all)
    def allowed_confidence(map)
      return 'low' if map.nil?
      return 'high' if map.state == 'covered' && map.probe_count.to_i >= 3
      return 'medium' if map.state == 'partial' || map.probe_count.to_i == 2

      'low'
    end

    def coverage_map_for(skill_data, discovered:)
      if discovered
        @coverage_maps.find do |m|
          m.is_discovered && m.skill_label.to_s.casecmp?(skill_data['skill_label'].to_s)
        end
      else
        @coverage_maps.find do |m|
          !m.is_discovered && m.skill_id.present? && m.skill_id == skill_data['skill_id']
        end || @coverage_maps.find do |m|
          !m.is_discovered && m.skill_label.to_s.casecmp?(skill_data['skill_label'].to_s)
        end
      end
    end

    # Validates BEFORE writing: an out-of-range level is rejected (never
    # clamped into a wrong value) and confidence must be a known level.
    def persist_skill!(portfolio, skill_data, discovered:)
      level      = Integer(skill_data['level'], exception: false)
      confidence = skill_data['confidence']

      unless level&.between?(1, 5) && PortfolioSkill::CONFIDENCE_LEVELS.include?(confidence)
        raise ArgumentError,
              "invalid portfolio skill #{skill_data['skill_label'].inspect}: " \
              "level=#{skill_data['level'].inspect} confidence=#{confidence.inspect}"
      end

      confidence = enforce_confidence(skill_data, confidence, discovered:)

      # NOTE: create through the class, not portfolio.portfolio_skills.create!.
      # The association target caches the new record; if this transaction rolls
      # back, the cached record stays "new" in memory and Portfolio#update!
      # (failure path) autosaves it again, resurrecting the orphan row.
      PortfolioSkill.create!(
        portfolio_id:       portfolio.id,
        skill_id:           discovered ? nil : skill_data['skill_id'],
        skill_label:        skill_data['skill_label'],
        is_discovered:      discovered,
        ai_level:           level,
        ai_confidence:      confidence,
        evidence:           Array(skill_data['evidence']).first(3),
        competency_summary: skill_data['competency_summary']
      )
    end
  end
end
