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
	module AWS
		class EC2

			def initialize()
				@object = ::AWS::EC2.new()
				@objects = []
				@objects = nil
			end

			def all()
				if(!@objects)
					@objects = []
					@objects << @object
					sts = AWS::STS.new()
					ServerUsers.new.assumable_roles.each do |arn|
						credentials = sts.assume_role(:role_arn => arn, :role_session_name => 'zepplen_aws')
						@objects << ::AWS::EC2.new(credentials[:credentials])
					end
				end
				return @objects
			end

			def method_missing(method, *args)
				@object.public_send(method, *args)
			end

		end
	end
end
