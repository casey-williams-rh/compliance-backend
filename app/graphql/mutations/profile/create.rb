# frozen_string_literal: true

module Mutations
  module Profile
    # Mutation to create a Profile
    class Create < BaseMutation
      graphql_name 'createProfile'

      argument :clone_from_profile_id, ID, required: true
      argument :business_objective_id, ID, required: false
      argument :benchmark_id, ID, required: true
      argument :name, String, required: true
      argument :ref_id, ID, required: true
      argument :description, String, required: false
      argument :business_objective_id, String, required: false
      argument :compliance_threshold, Float, required: false
      argument :selected_rule_ref_ids, [String], required: true
      field :profile, Types::Profile, null: false

      def resolve(args = {})
        policy = new_policy(args)
        profile = new_profile(args)

        Policy.transaction do
          policy.save!
          profile.update!(policy_object: policy, external: false)
          profile.update_rules(ref_ids: args[:selected_rule_ref_ids])
        end

        audit_mutation(profile, policy)
        { profile: profile }
      end

      private

      def new_policy(args)
        ::Policy.new(new_policy_options(args)).fill_from(
          profile: ::Profile.find(args[:clone_from_profile_id])
        )
      end

      def new_profile(args)
        ::Profile.new(new_profile_options(args)).fill_from_parent
      end

      def new_policy_options(args)
        {
          account_id: context[:current_user].account_id,
          name: args[:name],
          description: args[:description],
          business_objective_id: args[:business_objective_id],
          compliance_threshold: args[:compliance_threshold]
        }
      end

      def new_profile_options(args)
        {
          account_id: context[:current_user].account_id,
          parent_profile_id: args[:clone_from_profile_id]
        }
      end

      def audit_mutation(profile, policy)
        audit_success(
          "Created policy #{policy.id} with initial profile #{profile.id}" \
          ' including tailoring (no systems assigned yet)'
        )
      end
    end
  end
end
