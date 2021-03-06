#
# Cookbook Name:: gerrit
# Recipe:: default
#
# Copyright 2012, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

include_recipe "postgresql::server"
include_recipe "postgresql::ruby"
include_recipe "git"

node.default['gerrit']['war_file'] = File.basename(node['gerrit']['url'])
node.default['gerrit']['war_path'] = File.join(node['gerrit']['path'], node['gerrit']['war_file'])
node.default['gerrit']['bouncy_castle_war_path'] = File.join(node['gerrit']['site_path'], "lib", File.basename(node['gerrit']['bouncy_castle_url']))

directory node['gerrit']['path'] do
  owner "root"
  mode "0755"
end

user node['gerrit']['username'] do
  home node['gerrit']['site_path']
  system true
end

directory node['gerrit']['site_path'] do
  owner node['gerrit']['username']
end

directory File.join(node['gerrit']['site_path'], "etc") do
  owner node['gerrit']['username']
  mode "0755"
end

directory File.join(node['gerrit']['site_path'], "lib") do
  owner node['gerrit']['username']
  mode "0755"
end

remote_file node['gerrit']['war_path'] do
  source node['gerrit']['url']
  owner "root"
  mode "0644"
  checksum node['gerrit']['sha256']
end

postgresql_database_user node['gerrit']['username'] do
  connection ({:host => "127.0.0.1", :port => 5432, :username => 'postgres', :password => node['postgresql']['password']['postgres']})
  password node['gerrit']['db_password'] 
end

postgresql_database node['gerrit']['db_name'] do
  connection ({:host => "127.0.0.1", :port => 5432, :username => 'postgres', :password => node['postgresql']['password']['postgres']})
  encoding 'UTF-8'
  owner node['gerrit']['username']
end

remote_file node['gerrit']['bouncy_castle_war_path'] do
  source node['gerrit']['bouncy_castle_url']
  owner "root"
  mode "0644"
  checksum node['gerrit']['bouncy_castle_sha256']
end

template File.join(node['gerrit']['site_path'], 'etc', 'gerrit.config') do
  source "gerrit.config.erb"
  owner "root"
  mode "0644"
  notifies :restart, 'service[gerrit]'
end

template File.join(node['gerrit']['site_path'], 'etc', 'secure.config') do
  source "secure.config.erb"
  owner node['gerrit']['username']
  mode "0600"
  notifies :restart, 'service[gerrit]'
end

replications = search(:gerrit_replications, "*:*")

if replications
  template File.join(node['gerrit']['site_path'], 'etc', 'replication.config') do
    source "replication.config.erb"
    owner node['gerrit']['username']
    mode "0600"
    variables(:replications => replications)
    notifies :restart, 'service[gerrit]'
  end
    
  directory File.join(node['gerrit']['site_path'], '.ssh') do
    owner "gerrit2"
    mode "0700"
    action :create
    recursive true
  end
    
  # template File.join(node['gerrit']['site_path'], '.ssh', 'config') do
  #   source "ssh.config.erb"
  #   owner "gerrit2"
  #   mode "0644"
  #   variables(:replications => replications)
  #   notifies :restart, 'service[gerrit]'
  # end
                      
  # replications.each do |replication|
  #   if replication['repos']
  #     replication['repos'].each do |repo|
  #       keyFile = File.join(node['gerrit']['site_path'], '.ssh', "#{repo}-id_rsa")
  #       execute "generate ssh key for #{repo}." do
  #         creates "#{keyFile}.pub"
  #         command "ssh-keygen -t rsa -q -f #{keyFile} -P \"\""
  #       end
  #     end
  #   end
  # end
  
  # sshPath = File.join(node['gerrit']['site_path'], '.ssh')
  # execute "chmod keys." do
  #   command "chown -R #{node['gerrit']['username']}:#{node['gerrit']['username']} #{sshPath}"
  # end
end

execute "java -jar #{node['gerrit']['war_path']} init -d #{node['gerrit']['site_path']} --batch --no-auto-start" do
  user node['gerrit']['username']
  not_if { File.directory?(File.join(node['gerrit']['site_path'], "bin")) }
end

file "/etc/default/gerritcodereview" do
  owner "root"
  mode "0644"
  content <<EOH
GERRIT_SITE=#{node['gerrit']['site_path']}
EOH
end

include_recipe "nginx::source"

template "#{node['nginx']['dir']}/sites-available/gerrit.conf" do
  source      "nginx.conf.erb"
  owner       'root'
  group       'root'
  mode        '0644'
  variables(
    :host_name        => node['gerrit']['http_proxy']['host_name'],
    :host_aliases     => node['gerrit']['http_proxy']['host_aliases'],
    :listen_ports     => node['gerrit']['http_proxy']['listen_ports'],
    :max_upload_size  => node['gerrit']['http_proxy']['client_max_body_size']
  )
  notifies :restart, 'service[nginx]'
end

nginx_site "gerrit.conf" do
  enable true
end

template "/etc/init.d/gerrit" do
  source "gerrit.erb"
  owner "root"
  group "root"
  mode "0755"
end

# Do we need this if we enable/start it later?
# execute "start gerrit at boot" do
#   command "chkconfig --add gerrit"
#   not_if { File.exists?("/etc/rc3.d/S99gerrit") }  
# end

service "gerrit" do
  supports :restart => true
  start_command "/etc/init.d/gerrit start"
  stop_command "/etc/init.d/gerrit stop"
  restart_command "/etc/init.d/gerrit restart"
  status_command "ps auwwx | grep GerritCodeReview | grep gerrit2"
  provider Chef::Provider::Service::Init	
  action :start
end

