# encoding: utf-8

require_relative '../../../spec_helper'
require_relative '../../../../app/controllers/carto/api/database_groups_controller'
require 'rspec/mocks'

describe Carto::Api::GroupsController do
  include_context 'organization with users helper'

  describe 'Groups editor management' do

    before(:all) do
      @carto_organization = Carto::Organization.find(@organization.id)
      @carto_org_user_1 = Carto::User.find(@org_user_1.id)
      @group_1 = FactoryGirl.create(:random_group, display_name: 'g_1', organization: @carto_organization)
      @group_1_json = { 'id' => @group_1.id, 'organization_id' => @group_1.organization_id, 'name' => @group_1.name, 'display_name' => @group_1.display_name }
      @group_2 = FactoryGirl.create(:random_group, display_name: 'g_2', organization: @carto_organization)
      @group_2_json = { 'id' => @group_2.id, 'organization_id' => @group_2.organization_id, 'name' => @group_2.name, 'display_name' => @group_2.display_name }
      @group_3 = FactoryGirl.create(:random_group, display_name: 'g_3', organization: @carto_organization)
      @group_3_json = { 'id' => @group_3.id, 'organization_id' => @group_3.organization_id, 'name' => @group_3.name, 'display_name' => @group_3.display_name }
      @headers = {'CONTENT_TYPE'  => 'application/json', :format => "json" }
    end

    after(:all) do
      @group_1.destroy
      @group_2.destroy
      @group_3.destroy
    end

    before(:each) do
      @carto_organization.reload
    end

    it '#index returns 401 without authentication' do
      get_json api_v1_organization_groups_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id), {}, @headers do |response|
        response.status.should == 401
      end
    end

    it '#index returns groups with pagination metadata' do
      get_json api_v1_organization_groups_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id, api_key: @org_user_owner.api_key), {}, @headers do |response|
        response.status.should == 200
        expected_response = {
          groups: [ @group_1_json, @group_2_json, @group_3_json ],
          total_entries: 3,
          total_org_entries: 3
        }
        response.body.should == expected_response
      end
    end

    it '#index returns paginated groups with pagination metadata' do
      get_json api_v1_organization_groups_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id, api_key: @org_user_owner.api_key), { page: 2, per_page: 1, order: 'display_name' }, @headers do |response|
        response.status.should == 200
        expected_response = {
          groups: [ @group_2_json ],
          total_entries: 3,
          total_org_entries: 3
        }
        response.body.should == expected_response
      end
    end

    it '#index can search by name' do
      get_json api_v1_organization_groups_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id, api_key: @org_user_owner.api_key, q: @group_2.name), { page: 1, per_page: 1, order: 'display_name' }, @headers do |response|
        response.status.should == 200
        expected_response = {
          groups: [ @group_2_json ],
          total_entries: 1,
          total_org_entries: 3
        }
        response.body.should == expected_response
      end
    end

    it '#show returns a group' do
      get_json api_v1_organization_groups_show_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id, group_id: @group_1.id, api_key: @org_user_owner.api_key), { }, @headers do |response|
        response.status.should == 200
        response.body.should == @group_1_json.symbolize_keys
      end
    end

    it '#create fails if user is not owner' do
      post_json api_v1_organization_groups_create_url(user_domain: @org_user_1.username, organization_id: @carto_organization.id, api_key: @org_user_1.api_key), { display_name: 'willfail' }, @headers do |response|
        response.status.should == 400
      end
    end

    it '#create triggers group creation' do
      display_name = 'a new group'
      name = 'a_new_group'

      # Replacement for extension interaction
      fake_database_role = 'fake_database_role'
      fake_group_creation = Carto::Group.new_instance(@carto_organization.database_name, name, fake_database_role)
      fake_group_creation.save
      Carto::Group.expects(:create_group_extension_query).with(anything, name).returns(fake_group_creation)

      post_json api_v1_organization_groups_create_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id, api_key: @org_user_owner.api_key), { display_name: display_name }, @headers do |response|
        response.status.should == 200
        response.body[:id].should_not be_nil
        response.body[:organization_id].should == @carto_organization.id
        response.body[:name].should == name
        response.body[:display_name].should == display_name

        # Also check database data because Group changes something after extension interaction
        new_group = Carto::Group.find(response.body[:id])
        new_group.organization_id.should == @carto_organization.id
        new_group.name.should == name
        new_group.display_name.should == display_name
        new_group.database_role.should_not be_nil
      end
    end

    it '#update triggers group renaming' do
      group = @carto_organization.groups.first
      new_display_name = 'A Group Renamed'
      expected_new_name = 'A_Group_Renamed'

      Carto::Group.expects(:rename_group_extension_query).with(anything, group.name, expected_new_name)

      put_json api_v1_organization_groups_update_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id, group_id: group.id, api_key: @org_user_owner.api_key), { display_name: new_display_name }, @headers do |response|
        response.status.should == 200
        response.body[:id].should_not be_nil
        response.body[:organization_id].should == @carto_organization.id
        # INFO: since test doesn't actually trigger the extension we only check expectation on renaming call and display name
        response.body[:display_name].should == new_display_name

        # Also check database data because Group changes something after extension interaction
        new_group = Carto::Group.find(response.body[:id])
        new_group.organization_id.should == @carto_organization.id
        new_group.display_name.should == new_display_name
        new_group.database_role.should_not be_nil
      end
    end

    it '#add_member triggers group inclusion' do
      group = @carto_organization.groups.first
      user = @org_user_1

      Carto::Group.expects(:add_member_group_extension_query).with(anything, group.name, user.username)

      post_json api_v1_organization_groups_add_member_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id, group_id: group.id, api_key: @org_user_owner.api_key), { user_id: user.id }, @headers do |response|
        response.status.should == 200
        # INFO: since test doesn't actually trigger the extension we only check expectation on membership call
      end
    end

    it '#remove_member triggers group exclusion' do
      group = @carto_organization.groups.first
      user = @carto_org_user_1
      group.users << user
      group.save
      group.reload
      group.users.include?(user)

      Carto::Group.expects(:remove_member_group_extension_query).with(anything, group.name, user.username)

      delete_json api_v1_organization_groups_remove_member_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id, group_id: group.id, api_key: @org_user_owner.api_key, user_id: user.id), {}, @headers do |response|
        response.status.should == 200
        # INFO: since test doesn't actually trigger the extension we only check expectation on membership call
      end
    end

    it '#drops triggers deletion of existing groups' do
      group = @carto_organization.groups.first

      Carto::Group.expects(:destroy_group_extension_query).with(anything, group.name)

      delete_json api_v1_organization_groups_destroy_url(user_domain: @org_user_owner.username, organization_id: @carto_organization.id, group_id: group.id, api_key: @org_user_owner.api_key), { }, @headers do |response|
        response.status.should == 200

        # Extension is simulated, so we delete the group manually
        group.delete
      end
    end

  end

end