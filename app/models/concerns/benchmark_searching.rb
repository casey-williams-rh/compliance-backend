# frozen_string_literal: true

# Holder of scopes and scoped_search
module BenchmarkSearching
  extend ActiveSupport::Concern

  included do
    scoped_search on: %i[id ref_id title version]
    scoped_search relation: :profiles, on: :id, rename: :profile_ids,
                  aliases: %i[profile_id]
    scoped_search relation: :rules, on: :id, rename: :rule_ids,
                  aliases: %i[rule_id]
    scoped_search on: :os_major_version,
                  ext_method: 'os_major_version_search',
                  only_explicit: true, operators: ['=', '!='],
                  validator: ScopedSearch::Validators::INTEGER

    scope :os_major_version, lambda { |major, equals = true|
      where(os_major_version_query(major, equals))
    }

    scope :supported_os_minor_versions, lambda { |minor_versions|
      supported_os_minor_clauses(minor_versions).reduce(none) do |ors, clause|
        ors.or(where(*clause))
      end
    }

    scope :latest_supported, lambda {
      SupportedSsg.latest_per_os_major.inject(none) do |supported, ssg|
        supported.or(
          where(ref_id: ssg.ref_id,
                version: ssg.upstream_version || ssg.version)
        )
      end
    }
  end

  # class methods for benchmark searching
  module ClassMethods
    def os_major_version_like_condition(major)
      "%RHEL-#{major}"
    end

    def os_major_version_query(major, equals)
      ref_id = arel_table[:ref_id]
      condition = os_major_version_like_condition(major)
      equals ? ref_id.matches(condition) : ref_id.does_not_match(condition)
    end

    def os_major_version_search(_filter, operator, value)
      equals = operator == '=' ? ' ' : ' NOT '
      { conditions: "ref_id#{equals}like ?",
        parameter: [os_major_version_like_condition(value)] }
    end

    def supported_os_minor_clauses(minor_versions)
      minor_versions = [minor_versions].flatten.map(&:to_s)

      SupportedSsg.latest_map.map do |major, major_ssgs|
        ssg_versions = minor_versions.map do |minor_version|
          major_ssgs[minor_version]&.version
        end.compact.uniq

        next if ssg_versions.count.zero?

        ['benchmarks.ref_id LIKE ? AND benchmarks.version IN (?)',
         os_major_version_like_condition(major),
         ssg_versions]
      end.compact
    end

    def latest
      select(
        'DISTINCT ref_id, version, id, title'
      ).group_by(&:ref_id).map do |_, benchmarks|
        find_latest(benchmarks)
      end
    end

    def find_latest(benchmarks)
      benchmarks.max_by do |benchmark|
        Gem::Version.new(benchmark.version)
      end
    end
  end
end