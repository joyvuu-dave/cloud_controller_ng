module VCAP::CloudController
  module NameCharsetValidator
    private

    def validate_name_charset
      return if name.blank?
      return unless new? || column_changed?(:name)
      return unless db.database_type == :mysql
      return unless name.each_char.any? { |c| c.ord > 0xFFFF }

      errors.add(:name, Sequel.lit(
                          'contains characters that are not supported. ' \
                          'Please remove emoji or other special Unicode characters and try again.'
                        ))
    end
  end
end
