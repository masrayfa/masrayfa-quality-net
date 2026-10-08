# frozen_string_literal: true

require 'rails_helper'

# Regression lock for PRD-01 §3 (coverage state machine).
# The rule is enforced in Coverage::StateEngine#valid_transition? — verified
# correct during recon (todo 8, item B3), so this suite is expected GREEN.
RSpec.describe Coverage::StateEngine do
  # Readability helper: valid_transition? with positional args.
  def valid?(from, to, probe_count)
    described_class.valid_transition?(from: from, to: to, probe_count: probe_count)
  end

  def resolve(from, to, probe_count)
    described_class.resolve_state(current_state: from, proposed_state: to, probe_count: probe_count)
  end

  describe '.valid_transition?' do
    context 'HARD RULE: probe_count < 2 blocks any advance past initiated' do
      [0, 1].each do |count|
        it "rejects initiated -> partial at probe_count=#{count}" do
          expect(valid?('initiated', 'partial', count)).to be(false)
        end

        it "rejects partial -> covered at probe_count=#{count}" do
          expect(valid?('partial', 'covered', count)).to be(false)
        end
      end

      it 'still allows not_yet -> initiated at probe_count=0 (first touch is not gated)' do
        expect(valid?('not_yet', 'initiated', 0)).to be(true)
      end
    end

    context 'at probe_count >= 2 the gated steps are allowed' do
      [2, 3].each do |count|
        it "allows initiated -> partial at probe_count=#{count}" do
          expect(valid?('initiated', 'partial', count)).to be(true)
        end

        it "allows partial -> covered at probe_count=#{count}" do
          expect(valid?('partial', 'covered', count)).to be(true)
        end
      end
    end

    context 'forward-only adjacency' do
      it 'allows exactly the chain not_yet -> initiated -> partial -> covered' do
        expect(valid?('not_yet', 'initiated', 0)).to be(true)
        expect(valid?('initiated', 'partial', 2)).to be(true)
        expect(valid?('partial', 'covered', 2)).to be(true)
      end

      it 'rejects skip-ahead transitions even with plenty of probes' do
        expect(valid?('not_yet', 'partial', 5)).to be(false)
        expect(valid?('not_yet', 'covered', 5)).to be(false)
        expect(valid?('initiated', 'covered', 5)).to be(false)
      end

      it 'rejects backward transitions even with plenty of probes' do
        expect(valid?('initiated', 'not_yet', 5)).to be(false)
        expect(valid?('partial', 'not_yet', 5)).to be(false)
        expect(valid?('partial', 'initiated', 5)).to be(false)
        expect(valid?('covered', 'partial', 5)).to be(false)
        expect(valid?('covered', 'not_yet', 5)).to be(false)
      end

      it 'has no outgoing transition from covered' do
        %w[not_yet initiated partial covered].each do |to|
          expect(valid?('covered', to, 10)).to be(false)
        end
      end

      it 'rejects unknown states on either side' do
        expect(valid?('not_yet', 'discovered', 5)).to be(false)
        expect(valid?('bogus', 'partial', 5)).to be(false)
        expect(valid?('', 'initiated', 5)).to be(false)
      end
    end
  end

  describe '.resolve_state' do
    context 'skip-ahead (not_yet -> covered) walks ONE step at a time' do
      it 'stops at initiated when probe_count < 2' do
        expect(resolve('not_yet', 'covered', 0)).to eq('initiated')
        expect(resolve('not_yet', 'covered', 1)).to eq('initiated')
      end

      it 'stops at partial at probe_count=2 (covered is one step further)' do
        expect(resolve('not_yet', 'covered', 2)).to eq('covered')
        expect(resolve('not_yet', 'partial', 2)).to eq('partial')
      end

      it 'walks not_yet -> initiated -> partial at the gate, never jumping' do
        expect(resolve('not_yet', 'partial', 0)).to eq('initiated')
        expect(resolve('not_yet', 'partial', 1)).to eq('initiated')
        expect(resolve('not_yet', 'covered', 0)).to eq('initiated')
      end

      it 'never resolves to covered with probe_count < 2 from any state' do
        [0, 1].each do |count|
          %w[not_yet initiated partial].each do |from|
            expect(resolve(from, 'covered', count)).not_to eq('covered')
          end
        end
      end

      it 'stops a gated hop initiated -> covered at initiated below 2 probes' do
        expect(resolve('initiated', 'covered', 1)).to eq('initiated')
        expect(resolve('initiated', 'covered', 2)).to eq('covered')
      end
    end

    context 'no-op guards' do
      it 'is a no-op when the proposed state equals the current state' do
        expect(resolve('partial', 'partial', 0)).to eq('partial')
        expect(resolve('covered', 'covered', 0)).to eq('covered')
      end

      it 'is a no-op for an unknown proposed state' do
        expect(resolve('not_yet', 'discovered', 5)).to eq('not_yet')
        expect(resolve('initiated', 'whatever', 5)).to eq('initiated')
      end

      it 'ignores backward proposals' do
        expect(resolve('partial', 'not_yet', 5)).to eq('partial')
        expect(resolve('covered', 'initiated', 5)).to eq('covered')
      end

      it 'keeps covered covered regardless of probes' do
        expect(resolve('covered', 'covered', 0)).to eq('covered')
        expect(resolve('covered', 'not_yet', 10)).to eq('covered')
      end
    end
  end
end
