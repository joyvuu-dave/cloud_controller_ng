module VCAP::CloudController
  class DropletListFetcher
    def initialize(message:)
      @message = message
    end

    def fetch_all
      dataset = DropletModel.dataset
      filter(nil, dataset)
    end

    def fetch_for_spaces(space_guids:)
      @space_guids = space_guids
      dataset = DropletModel.dataset
      filter(nil, dataset)
    end

    def fetch_for_app
      app = AppModel.where(guid: @message.app_guid).eager(:space, space: :organization).all.first
      return nil unless app

      [app, filter(app, app.droplets_dataset)]
    end

    def fetch_for_package
      package = PackageModel.where(guid: @message.package_guid).eager(:space, space: :organization).all.first
      return nil unless package

      [package, filter(nil, package.droplets_dataset)]
    end

    private

    def filter(app, dataset)
      if @message.requested?(:current) && app
        dataset = dataset.extension(:null_dataset)
        return dataset.nullify unless app.droplet

        dataset = dataset.where(guid: app.droplet.guid)
      end

      if @message.requested?(:app_guids)
        dataset = dataset.where(app_guid: @message.app_guids)
      end

      if @message.requested?(:states)
        dataset = dataset.where(state: @message.states)
      end

      droplet_table_name = DropletModel.table_name
      if @message.requested?(:guids)
        dataset = dataset.where("#{droplet_table_name}__guid".to_sym => @message.guids)
      end

      if @message.requested?(:organization_guids)
        space_guids_from_orgs = Organization.where(guid: @message.organization_guids).map(&:spaces).flatten.map(&:guid)
        dataset = dataset.select_all(droplet_table_name).
                  join_table(:inner, AppModel.table_name, { guid: Sequel[:droplets][:app_guid], space_guid: space_guids_from_orgs }, { table_alias: :apps_orgs })
      end

      if scoped_space_guids.present?
        dataset = dataset.select_all(droplet_table_name).
                  join_table(:inner, AppModel.table_name, { guid: Sequel[:droplets][:app_guid], space_guid: scoped_space_guids }, { table_alias: :apps_spaces })
      end

      if @message.requested? :label_selector
        dataset = LabelSelectorQueryGenerator.add_selector_queries(
          label_klass: DropletLabelModel,
          resource_dataset: dataset,
          requirements: @message.requirements,
          resource_klass: DropletModel,
          prefilter_labels_by_resource_dataset: scoped_space_guids.present?,
        )
      end

      dataset.exclude(state: DropletModel::STAGING_STATE).qualify(DropletModel.table_name)
    end

    def scoped_space_guids(permitted_space_guids: @space_guids, filtered_space_guids: @message.space_guids)
      return nil unless permitted_space_guids || filtered_space_guids
      return filtered_space_guids & permitted_space_guids if filtered_space_guids && permitted_space_guids
      return permitted_space_guids if permitted_space_guids
      return filtered_space_guids if filtered_space_guids
    end
  end
end
