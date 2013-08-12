#Copyright 2013 Mark Trimmer
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

module ZepplenAWS

	# = Manage Server Users
	#
	# This class is intended to be used by both the CLI scripts provided, and 3rd party tools
	# written by you! 
	#
	# The metadata for the environment (options set using the configure method), are stored
	# in a DynamoDB row along with the users. The default name for this row is '__metadata__'.
	# 
	#
	class ServerUsers

		# Server Users
		#
		# @param optional [String] Dynamo table name, if not provided will pull from Env, or default to 'users'
		def initialize(dynamo_table = nil)
			@dynamo_table = dynamo_table || Env[:dynamo_table] || 'users'

			# I don't there there is any way to reach this error state....
			if(@dynamo_table == nil)
				raise Exceptions::Users::MissingOption, "DynamoDB Table Name Required"
			end

			@dynamo = AWS::DynamoDB.new()
			@table = @dynamo.tables[@dynamo_table]
			@table.hash_key = {:type => :string}
			@table.range_key = {:user_name => :string}
			if(!@table.exists?)
				raise Exceptions::Users::NoDynamoTable, "Could Not Access DynamoDB Table: #{@dynamo_table}"
			end
			@local_user_data = {}

			Env[:dynamo_table] = @dynamo_table
			@metadata = @table.items['METADATA', '__metadata__']
		end

		# Exists?
		#
		# Reflects if there is a _metadata_ row availible. If not use needs to configure environment.
		def exists?()
			return @metadata.exists?
		end

		# Identity
		#
		# This number is incremented any time a configuration changes, or a user profile is updated.
		# We use this to reduce the number of dynamo calls each client has to make.
		#
		# @return [Integer] Identity
		def identity()
			return @metadata.attributes[:identity].to_i
		end

		# User File Bucket
		#
		# @return [String] Name of S3 Bucket user files are stored in
		def user_file_bucket()
			return @metadata.attributes[:user_file_bucket]
		end

		# Set User File Bucket
		#
		# @param [String] Name of S3 Bucket to store user files in. Nil to disable feature
		def user_file_bucket=(s3_path)
			update_metadata(:user_file_bucket => s3_path)
			return nil
		end

		# Assumable Roles
		#
		# @return [Array] List of AWS ARNs that can be assumed by the provided keys.
		def assumable_roles()
			return @metadata.attributes[:assumable_roles].to_a
		end

		# Set Assumable Roles
		#
		# @param [Array] Aws ARNs of roles that can be assumed by the provided keys.
		def assumable_roles=(roles)
			update_metadata(:assumable_roles => roles)
		end

		# Max Key Age
		#
		# Number of Days to continue using an SSH Key before it is expired and removed from all servers
		#
		# @return [Integer] Max key age (days)
		def max_key_age()
			return @metadata.attributes[:max_key_age].to_i
		end

		# Set Max Key Age
		#
		# Number of Days to continue using an SSH Key before it is expired and removed from all servers
		#
		# @param [Integer] Max key age (days)
		def max_key_age=(key_age)
			update_metadata(:key_age => key_age)
			return nil
		end

		# Next UID
		#
		# Next linux uid to use. We make sure that each user's uid is consistant accross all servers. This
		# prevents users from having broken permissions when they are removed and re-added to an instance.
		#
		# @return [Integet] Next uid
		def next_uid()
			return @metadata.attributes[:next_uid].to_i
		end

		# Set Next UID
		#
		# Next linux uid to use. We make sure that each user's uid is consistant accross all servers. This
		# prevents users from having broken permissions when they are removed and re-added to an instance.
		#
		# Warning: Be sure not to set to a range already used by existing users, or existing accounts on your servers.
		#
		# @param [Integer] Next uid
		def next_uid=(next_uid)
			update_metadata(:next_uid => next_uid)
			return nil
		end

		# Sudo Group
		#
		# Group that user will be added to grant sudo access to an instance.
		#
		# @return [String] sudo group
		def sudo_group()
			return @metadata.attributes[:sudo_group]
		end

		# Set Sudo Group
		#
		# Group that user will be added to grant sudo access to an instance. Please be sure this group is configured
		# correctly on all of your instances. Group should grant NOPASSWD access, as this script will NOT set a
		# passwor for any user.
		#
		# @param [String] sudo group
		def sudo_group=(sudo_group)
			update_metadata(:sudo_group => sudo_group)
			return nil
		end

		# Tags
		#
		# Returns the list of EC2 tags accessible to taget users's access.
		#
		# @return [Array] List of EC2 tags valid for granting user access to servers.
		def tags()
			return @metadata.attributes[:tags].to_a
		end

		# Set Tags
		#
		# Overwrite existing tags with new Array of EC2 Tags
		#
		# @param [Array[String]] EC2 Tags that are valid for granting user access to servers.
		def tags=(tags)
			update_metadata(:tags => tags)
			@metadata.attributes.update do |u|
				u.set(:tags => tags)
				u.add(:idenity => 1)
			end
			return nil
		end

		# Add Tags
		#
		# Add tags witn Array of EC2 Tags
		#
		# @param [Array[String]] EC2 Tags that are valid for granting user access to servers.
		def add_tags(tags)
			@metadata.attributes.update do |u|
				u.add(:tags => tags)
				u.add(:idenity => 1)
			end
			return nil
		end

		# Remove Tags
		#
		# Revmove tags witn Array of EC2 Tags
		#
		# @param [Array[String]] EC2 Tags that are no longer valid for granting user access to servers.
		def remove_tags(tags)
			@metadata.attributes.update do |u|
				u.delete(:tags => tags)
				u.add(:idenity => 1)
			end
			return nil
		end

		# Configure Envoronment
		#
		# Allows users to set multiple parameters at once
		# == Valid Parameters
		# :next_uid, :max_key_age, :tags, :sudo_group, :user_file_bucket
		#
		# @param [Hash] Parameter values to set
		def configure(config)
			valid_configs = [:next_uid, :max_key_age, :tags, :sudo_group, :assumable_roles]
			to_use_config = config.select{|k,v| valid_configs.include?(k)}
			@metadata.attributes.update do |item_data|
				item_data.set(to_use_config)
				if(config.has_key?(:user_file_bucket))
					if(config[:user_file_bucket])
						item_data.set(:user_file_bucket => config[:user_file_bucket])
					else
						item_data.delete(:user_file_bucket)
					end
				end
				if(@metadata.attributes[:identity] == nil)
					item_data.set(:identity => 0)
				else
					item_data.add(:identity => 1)
				end
			end
		end

		# Users
		#
		# Returns an array of ServerUser objects
		#
		# @return [Hash[ServerUser]] 
		def users()
			users = {}
			@table.items.where(:type => 'USER').each do |user_row|
				users[user_row.attributes[:user_name]] = ServerUser.new(user_row.attributes[:user_name], @dynamo_table, user_row, @metadata, self)
			end
			return users
		end

		# Fetch Tags from all Instances
		#
		# This is a utility function to fetch all the Tags accross all assumable AWS accounts.
		# This function should fetch the tags faster than iterating accross all the instances.
		# Note, this function will ALWAYS return the name tag.
		#
		# @param [Array] List of tags to limit search to.
		# @return [Hash]
		def get_all_instance_tags(limit_tags=nil)
			ec2 = AWS::EC2.new()
			if(!limit_tags)
				limit_tags = @server_users.tags
			end
			data = {}
			::AWS.memoize do
				ec2.all.each do |e|
					filter_tags = limit_tags.dup
					filter_tags << 'Name'
					e.tags.filter('resource-type', 'instance').filter('key', filter_tags).each do |tag|
						if(!data.has_key?(tag.resource.id))
							data[tag.resource.id] = {}
						end
						data[tag.resource.id][tag.key] = tag.value
					end
				end
			end
			return data
		end

		private

		def update_metadata(data)
			@metadata.attributes.update do |u|
				data.each_pair do |key, value|
					if(value)
						u.set(key => value)
					else
						u.delete(key)
					end
				end
				u.add(:identity => 1)
			end
		end

		def update_required?(local_users)
			if(!File.readable?(local_users))
				return true
			end
			@local_user_data = Yaml.load(local_users)
			return false
		end

	end
end
