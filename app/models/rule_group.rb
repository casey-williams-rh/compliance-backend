# frozen_string_literal: true

# OpenSCAP RuleGroup
class RuleGroup < ApplicationRecord
  # Need to set primary key format to work with uuid primary key column
  has_ancestry(primary_key_format: %r{\A[\w\-]+(\/[\w\-]+)*\z})

  has_many :left_rule_group_relationships, dependent: :delete_all, foreign_key: :left_id,
                                           inverse_of: :left, class_name: 'RuleGroupRelationship'
  has_many :right_rule_group_relationships, dependent: :delete_all, foreign_key: :right_id,
                                            inverse_of: :right, class_name: 'RuleGroupRelationship'
  has_many :rules, -> { order(:precedence) }, dependent: :nullify, inverse_of: :rule_group

  has_many :rules_with_references, lambda {
    left_outer_joins(:rule_references_container).select(
      'rules.*', 'rule_references_containers.rule_references AS references'
    )
  }, inverse_of: :rule_group, dependent: :nullify, class_name: 'Rule'

  belongs_to :benchmark, class_name: 'Xccdf::Benchmark'

  validates :title, presence: true
  validates :ref_id, uniqueness: { scope: %i[benchmark_id] }, presence: true
  validates :description, presence: true
  validates :benchmark_id, presence: true

  def self.from_openscap_parser(op_rule_group, existing: nil, benchmark_id: nil, parent_id: nil, precedence: nil)
    rule_group = existing || new(ref_id: op_rule_group.id, benchmark_id: benchmark_id)

    rule_group.assign_attributes(title: op_rule_group.title,
                                 description: op_rule_group.description,
                                 rationale: op_rule_group.rationale,
                                 precedence: precedence,
                                 parent_id: parent_id)

    rule_group
  end
end
