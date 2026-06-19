Pod::Spec.new do |s|
  s.name             = "ThreadHive"
  s.version          = "1.0.0"
  s.summary          = "Native in-app messaging for the ThreadHive support bot + human agents."
  s.description      = <<-DESC
    ThreadHive's native iOS chat SDK: AI Q&A (RAG) with citations, handoff to human
    agents with live polling, product cards, bot action confirmations, attachments,
    identify (HMAC), and theming from your published widget config. No third-party deps.
  DESC
  s.homepage         = "https://threadhive.io"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "ThreadHive" => "support@threadhive.io" }
  s.source           = { :git => "https://github.com/rajgupttaa/Threadhive-ios-SDK.git", :tag => "#{s.version}" }

  s.swift_version    = "5.9"
  s.ios.deployment_target = "15.0"

  s.source_files     = "Sources/ThreadHive/**/*.swift"
  s.frameworks       = "Foundation", "Security"
end
