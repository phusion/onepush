task :install_language_runtime => :install_essentials do
  log_notice "Installing language runtime..."
  case APP_CONFIG.type
  when 'ruby'
    invoke :install_ruby_runtime
    install_common_ruby_app_dependencies
  when 'nodejs'
    invoke :install_nodejs_runtime
  end
end
