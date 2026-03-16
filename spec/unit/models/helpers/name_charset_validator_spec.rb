require 'spec_helper'
require 'models/helpers/name_charset_validator'

module VCAP::CloudController
  RSpec.describe NameCharsetValidator do
    let(:test_class) do
      Class.new(Sequel::Model(:apps)) do
        include NameCharsetValidator

        def validate
          validate_name_charset
        end
      end
    end

    let(:instance) { test_class.new(name: 'placeholder') }
    let(:db) { instance.db }

    describe '#validate_name_charset' do
      context 'when database is postgres' do
        before { allow(db).to receive(:database_type).and_return(:postgres) }

        it 'allows emoji characters' do
          instance.name = "\u{1F379}"
          instance.validate
          expect(instance.errors.on(:name)).to be_nil
        end

        it 'allows BMP unicode characters' do
          instance.name = "\u{9632}\u{5FA1}\u{529B}\u{00A1}"
          instance.validate
          expect(instance.errors.on(:name)).to be_nil
        end
      end

      context 'when database is mysql' do
        before { allow(db).to receive(:database_type).and_return(:mysql) }

        it 'rejects emoji characters' do
          instance.name = "\u{1F379}"
          instance.validate
          expect(instance.errors.on(:name)).to include(match(/characters that are not supported/))
        end

        it 'rejects mixed emoji and ascii' do
          instance.name = "my-app-\u{1F680}"
          instance.validate
          expect(instance.errors.on(:name)).to include(match(/characters that are not supported/))
        end

        it 'includes actionable guidance in the error message' do
          instance.name = "\u{1F379}"
          instance.validate
          expect(instance.errors.on(:name)).to include(match(/remove emoji/))
        end

        it 'allows BMP unicode characters' do
          instance.name = "\u{9632}\u{5FA1}\u{529B}\u{00A1}"
          instance.validate
          expect(instance.errors.on(:name)).to be_nil
        end

        it 'allows standard ascii characters' do
          instance.name = 'my-app'
          instance.validate
          expect(instance.errors.on(:name)).to be_nil
        end

        it 'allows Japanese characters' do
          instance.name = "\u{30A2}\u{30D7}\u{30EA}"
          instance.validate
          expect(instance.errors.on(:name)).to be_nil
        end

        it 'rejects non-emoji supplementary plane characters' do
          instance.name = "\u{1D11E}"
          instance.validate
          expect(instance.errors.on(:name)).to include(match(/characters that are not supported/))
        end
      end

      context 'when name is nil' do
        it 'does not add charset errors' do
          instance.name = nil
          instance.validate
          expect(instance.errors.on(:name)).to be_nil
        end
      end

      context 'when name is empty' do
        it 'does not add charset errors' do
          instance.name = ''
          instance.validate
          expect(instance.errors.on(:name)).to be_nil
        end
      end

      context 'when name has not changed on an existing record' do
        before { allow(db).to receive(:database_type).and_return(:mysql) }

        it 'skips validation' do
          allow(instance).to receive(:new?).and_return(false)
          allow(instance).to receive(:column_changed?).with(:name).and_return(false)
          instance.name = 'my-app'
          instance.validate
          expect(instance.errors.on(:name)).to be_nil
        end
      end

      context 'when name has changed on an existing record' do
        before { allow(db).to receive(:database_type).and_return(:mysql) }

        it 'runs validation' do
          allow(instance).to receive(:new?).and_return(false)
          allow(instance).to receive(:column_changed?).with(:name).and_return(true)
          instance.name = "\u{1F379}"
          instance.validate
          expect(instance.errors.on(:name)).to include(match(/characters that are not supported/))
        end
      end

      context 'when record is new' do
        before { allow(db).to receive(:database_type).and_return(:mysql) }

        it 'runs validation even though column_changed? may be false' do
          allow(instance).to receive(:new?).and_return(true)
          allow(instance).to receive(:column_changed?).with(:name).and_return(false)
          instance.name = "\u{1F379}"
          instance.validate
          expect(instance.errors.on(:name)).to include(match(/characters that are not supported/))
        end
      end
    end
  end
end
