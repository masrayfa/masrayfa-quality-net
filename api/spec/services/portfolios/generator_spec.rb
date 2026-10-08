# frozen_string_literal: true

require 'rails_helper'

# B2 regression lock: Portfolios::Generator#save_skills must be transactional
# and must reject invalid level/confidence instead of persisting partially.
#
# Red-first history: the malformed skill is deliberately SECOND so the
# pre-fix code commits the first row before raising (orphan row on a failed
# portfolio). See .omo/evidence/25-fix-b2.txt.
RSpec.describe Portfolios::Generator do
  # The injected seam from Generator#initialize(session:, gemini_client:).
  def fake_gemini(response)
    Class.new do
      define_method(:initialize) { |payload| @payload = payload }
      define_method(:generate_content) { |_prompt, temperature: nil| @payload }
    end.new(response)
  end

  def make_session
    org = Organization.create!(
      name: 'Tenant A', scheme: 'tenant-a', identifier: 'tenant-a', host: 'tenant-a.example.com'
    )
    assessment = Assessment.create!(
      tenant_id: org.id, created_by: 1, name: 'Backend Engineer', time_limit_min: 30
    )
    Session.create!(tenant_id: org.id, assessment_id: assessment.id)
  end

  def valid_skill(label: 'React / Frontend Development')
    {
      'skill_id'           => 'sk-eng-001',
      'skill_label'        => label,
      'level'              => 3,
      'confidence'         => 'high',
      'evidence'           => ['quote 1', 'quote 2'],
      'competency_summary' => 'Consistent L3 behavior.'
    }
  end

  # Returns the raised error, or nil when the generator does not raise.
  def run_generator(session, response)
    described_class.new(session: session, gemini_client: fake_gemini(response)).call
    nil
  rescue StandardError => e
    e
  end

  describe '#call with malformed skill data (B2)' do
    it 'rolls back and leaves the portfolio failed when the 2nd skill confidence is invalid' do
      session  = make_session
      response = {
        'configured_skills' => [
          valid_skill,
          valid_skill(label: 'PostgreSQL').merge('confidence' => 'certain')
        ]
      }

      error = run_generator(session, response)

      expect(error).not_to be_nil, 'generator must raise on an invalid confidence'
      portfolio = session.reload.portfolio
      expect(portfolio.generation_status).to eq('failed')
      expect(portfolio.portfolio_skills.reload.count).to eq(0),
        'expected rollback to leave ZERO skill rows, ' \
        "found #{portfolio.portfolio_skills.count} (partial persistence)"
    end

    it 'rolls back and leaves the portfolio failed when the 2nd skill level is out of range' do
      session  = make_session
      response = {
        'configured_skills' => [
          valid_skill,
          valid_skill(label: 'PostgreSQL').merge('level' => 9)
        ]
      }

      error = run_generator(session, response)

      expect(error).not_to be_nil, 'generator must raise on an out-of-range level'
      portfolio = session.reload.portfolio
      expect(portfolio.generation_status).to eq('failed')
      expect(portfolio.portfolio_skills.reload.count).to eq(0),
        'expected rollback to leave ZERO skill rows, ' \
        "found #{portfolio.portfolio_skills.count} (out-of-range level persisted)"
    end

    it 'still persists every skill and completes for a valid response (positive control)' do
      session  = make_session
      response = {
        'configured_skills' => [valid_skill, valid_skill(label: 'PostgreSQL').merge('level' => 4)],
        'discovered_skills' => [valid_skill(label: 'Micro-frontend Architecture').merge('skill_id' => nil)]
      }

      error = run_generator(session, response)

      expect(error).to be_nil
      portfolio = session.reload.portfolio
      expect(portfolio.generation_status).to eq('complete')
      expect(portfolio.portfolio_skills.count).to eq(3)
      expect(portfolio.portfolio_skills.pluck(:ai_level)).to contain_exactly(3, 4, 3)
    end
  end

  # ENF-1: confidence is capped by the session's coverage evidence (PRD-01 §5):
  #   high   — probe_count >= 3 AND state covered
  #   medium — probe_count == 2 OR state partial
  #   low    — anything else
  # The LLM may never talk the server into a stronger claim than coverage
  # supports (previously the prompt was the only enforcement).
  describe '#call confidence enforcement (ENF-1)' do
    def coverage_for(session, state:, probe_count:, discovered: false)
      session.coverage_maps.create!(
        skill_id:      discovered ? nil : 'sk-eng-001',
        skill_label:   'React / Frontend Development',
        is_discovered: discovered,
        state:         state,
        probe_count:   probe_count
      )
    end

    def persisted_confidence(claimed:, state: nil, probe_count: nil, with_map: true)
      session = make_session
      coverage_for(session, state: state, probe_count: probe_count) if with_map
      response = { 'configured_skills' => [valid_skill.merge('confidence' => claimed)] }

      error = run_generator(session, response)
      expect(error).to be_nil, "generator raised: #{error&.message}"
      session.reload.portfolio.portfolio_skills.find_by!(skill_label: 'React / Frontend Development').ai_confidence
    end

    it 'caps a claimed high to low when the skill has no coverage map' do
      expect(persisted_confidence(claimed: 'high', with_map: false)).to eq('low')
    end

    it 'caps a claimed high to low at probe_count 1 / initiated' do
      expect(persisted_confidence(claimed: 'high', state: 'initiated', probe_count: 1)).to eq('low')
    end

    it 'caps a claimed high to medium at probe_count 2 / partial' do
      expect(persisted_confidence(claimed: 'high', state: 'partial', probe_count: 2)).to eq('medium')
    end

    it 'keeps high when coverage is covered with probe_count >= 3' do
      expect(persisted_confidence(claimed: 'high', state: 'covered', probe_count: 3)).to eq('high')
    end

    it 'never upgrades a conservative claim' do
      expect(persisted_confidence(claimed: 'low', state: 'covered', probe_count: 5)).to eq('low')
    end

    it 'matches discovered skills by label and applies the same cap' do
      session = make_session
      coverage_for(session, state: 'partial', probe_count: 2, discovered: true)
      response = {
        'discovered_skills' => [valid_skill.merge('skill_id' => nil, 'confidence' => 'high')]
      }

      error = run_generator(session, response)

      expect(error).to be_nil
      skill = session.reload.portfolio.portfolio_skills.find_by!(skill_label: 'React / Frontend Development')
      expect(skill.ai_confidence).to eq('medium')
    end
  end
end
