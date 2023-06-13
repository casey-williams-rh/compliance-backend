# frozen_string_literal: true

require 'test_helper'
require './db/migrate/20200106134953_add_unique_index_to_benchmarks'
require 'sidekiq/testing'

class DuplicateBenchmarkResolverTest < ActiveSupport::TestCase
  setup do
    # rubocop:disable Lint/SuppressedException
    begin
      ActiveRecord::Migration.suppress_messages do
        AddUniqueIndexToBenchmarks.new.down
      end
    rescue ArgumentError # if index doesn't exist
    end
    # rubocop:enable Lint/SuppressedException

    @benchmark = FactoryBot.create(:benchmark)
    @rule = FactoryBot.create(:rule, benchmark: @benchmark)
    @profile = FactoryBot.create(:canonical_profile, benchmark: @benchmark)

    assert_difference('Xccdf::Benchmark.count' => 1) do
      (@dup_benchmark = @benchmark.dup)
        .assign_attributes(created_at: @benchmark.created_at + 1.minute)
      @dup_benchmark.save(validate: false)
    end
  end

  test 'resolves identical benchmarks' do
    assert_difference('Xccdf::Benchmark.count' => -1) do
      DuplicateBenchmarkResolver.run!
    end
  end

  test 'resolves rules from a duplicate benchmark with the same rule ref_id' do
    assert_difference('Rule.count' => 2) do
      @rule.dup.update!(ref_id: 'foo', benchmark: @benchmark)
      @rule.dup.update!(ref_id: 'foo', benchmark: @dup_benchmark)
    end

    assert_difference('Rule.count' => -1) do
      DuplicateBenchmarkResolver.run!
    end
  end

  test 'resolves rules from a duplicate benchmark with different rule ref_id' do
    assert_difference('Rule.count' => 2) do
      @rule.dup.update!(ref_id: 'foo', benchmark: @benchmark)
      @rule.dup.update!(ref_id: 'foo2', benchmark: @dup_benchmark)
    end

    assert_difference('Rule.count' => 0) do
      DuplicateBenchmarkResolver.run!
    end
  end

  test 'resolves profiles from a duplicate benchmark ' \
       'with the same profile ref_id' do
    assert_difference('Profile.count' => 2) do
      @profile.dup.update!(ref_id: 'foo', benchmark: @benchmark)
      @profile.dup.update!(ref_id: 'foo', benchmark: @dup_benchmark)
    end

    assert_difference('Profile.count' => -1) do
      DuplicateBenchmarkResolver.run!
    end
  end

  test 'resolves profiles from a duplicate benchmark ' \
       'with different profile ref_id' do
    assert_difference('Profile.count' => 2) do
      @profile.dup.update!(ref_id: 'foo', benchmark: @benchmark)
      @profile.dup.update!(ref_id: 'foo2', benchmark: @dup_benchmark)
    end

    assert_difference('Profile.count' => 0) do
      DuplicateBenchmarkResolver.run!
    end
  end

  test 'fails if parent_profile of migrated profile is not found' do
    parent = @profile.dup
    p = @profile.dup
    dup_parent = @profile.dup
    dup_p = @profile.dup
    assert_difference('Profile.count' => 4) do
      parent.update!(ref_id: 'bar', benchmark: @benchmark)
      p.update!(ref_id: 'bar2', benchmark: @benchmark,
                parent_profile_id: parent.id)

      dup_parent.update!(ref_id: 'foo',
                         benchmark: @dup_benchmark)
      dup_p.update!(ref_id: 'foo2', benchmark: @dup_benchmark,
                    parent_profile_id: dup_parent.id)
    end

    assert_equal parent.id, p.parent_profile_id
    assert_equal dup_parent.id, dup_p.parent_profile_id

    assert_raises(ActiveRecord::RecordNotFound) do
      DuplicateBenchmarkResolver.run!
    end
  end

  test 'resolves parent_profile of migrated profiles' do
    account1 = FactoryBot.create(:account)
    account2 = FactoryBot.create(:account)
    parent = @profile.dup
    p = @profile.dup
    dup_parent = @profile.dup
    dup_p = @profile.dup
    assert_difference('Profile.count' => 4) do
      parent.update!(ref_id: 'foo', benchmark: @benchmark)
      p.update!(ref_id: 'foo2', benchmark: @benchmark,
                account: account1, parent_profile_id: parent.id)

      dup_parent.update!(ref_id: 'foo',
                         benchmark: @dup_benchmark)
      dup_p.update!(ref_id: 'foo2', benchmark: @dup_benchmark,
                    account: account2, parent_profile_id: dup_parent.id)
    end

    assert_equal parent.id, p.parent_profile_id
    assert_equal dup_parent.id, dup_p.parent_profile_id

    assert_difference('Profile.count' => -2) do
      DuplicateBenchmarkResolver.run!
    end

    assert dup_p.parent_profile_id == dup_parent.id ||
           dup_p.parent_profile_id == parent.id
  end
end
