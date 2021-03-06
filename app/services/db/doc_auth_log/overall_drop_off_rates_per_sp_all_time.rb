module Db
  module DocAuthLog
    class OverallDropOffRatesPerSpAllTime
      include DropOffRatesHelper

      def call(title, issuer)
        drop_off_rates(title: title, issuer: issuer)
      end

      private

      def verified_user_counts_query
        <<~SQL
          select count(*) from identities
          where service_provider='#{issuer}' and ial>=2
          and user_id in (select user_id from doc_auth_logs where #{images_or_piv_cac_submitted})
          and user_id in (select user_id from profiles)
        SQL
      end

      def drop_offs_query
        <<~SQL
          #{select_counts_from_doc_auth_logs}
          where issuer='#{issuer}' and #{images_or_piv_cac_submitted}
        SQL
      end
    end
  end
end
