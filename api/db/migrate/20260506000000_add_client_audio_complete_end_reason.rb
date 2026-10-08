# frozen_string_literal: true

# B1: `audio_complete` must never assert `all_covered` from an unverified client
# claim. When the server coverage map does not verify the claim, the session is
# ended with this truthful reason instead (it still ends — no stall).
class AddClientAudioCompleteEndReason < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    execute "ALTER TYPE interview.end_reason ADD VALUE IF NOT EXISTS 'client_audio_complete'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'PostgreSQL enum values cannot be removed safely'
  end
end
