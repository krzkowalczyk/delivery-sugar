resource_name :delivery_terraform

property :plan_dir, String, required: true
property :lock, [TrueClass, FalseClass], required: false, default: false
property :backend_config, String, required: false

default_action :test

action :init do
  tf('init')
end

action :plan do
  tf('plan')
end

action :apply do
  tf('apply')
end

action :show do
  tf('show')
end

action :destroy do
  tf('destroy')
end

action :test do
  %w(init plan apply show destroy).each { |x| tf(x) }
end

action_class do
  require 'json'
  include Chef::Mixin::ShellOut
  include DeliverySugar::DSL

  def tf(action)
    preflight
    converge_by "[Terraform] Run action :#{action} " \
      "with *.tf files in #{new_resource.plan_dir}\n" do
      run(action)
      new_resource.updated_by_last_action(true)
    end
  end

  def preflight
    msg = 'Terraform preflight check: No such path for'
    fail "#{msg} plan_dir: #{new_resource.plan_dir}" unless ::File.exist?(
      new_resource.plan_dir
    )
    return if new_resource.backend_config.nil?
    fail "#{msg} backend-config: #{new_resource.backend_config}" unless ::File.exist?(
      new_resource.backend_config
    )
  end

  def cmd(action)
    case action
    when 'init'
      if new_resource.backend_config.nil?
        "terraform #{action} -lock=#{new_resource.lock} -input=false"
      else
        "terraform #{action} -lock=#{new_resource.lock} -input=false -backend-config=#{new_resource.backend_config}"
      end
    when 'plan'
      "terraform #{action} -lock=#{new_resource.lock} -input=false"
    when 'apply'
      "terraform #{action} -lock=#{new_resource.lock} -input=false -auto-approve"
    when 'destroy'
      "terraform #{action} -lock=#{new_resource.lock} -force"
    when 'show'
      "terraform #{action}"
    when 'state pull'
      "terraform #{action} 2>/dev/null"
    end
  end

  def state
    s = shell_out(cmd('state pull'), cwd: new_resource.plan_dir).stdout
    s == '' ? {} : JSON.parse(s)
  end

  def save_state
    node.run_state['terraform-state'] = state
    Chef::Log.info("Terraform state updated in node.run_state['terraform-state']")
  end

  def run(action)
    shell_out!(cmd(action), cwd: new_resource.plan_dir, live_stream: STDOUT)
  rescue Mixlib::ShellOut::ShellCommandFailed, Mixlib::ShellOut::CommandTimeout
    shell_out(cmd('destroy'), cwd: new_resource.plan_dir, live_stream: STDOUT)
    raise
  ensure
    save_state
  end
end
