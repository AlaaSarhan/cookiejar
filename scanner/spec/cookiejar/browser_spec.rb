# frozen_string_literal: true

RSpec.describe Cookiejar::Browser do
  let(:dir) { Dir.mktmpdir }
  let(:installed) { File.join(dir, "chrome-headless-shell").tap { |p| File.write(p, "") && File.chmod(0o755, p) } }
  let(:messages) { [] }

  before do
    stub_const("#{described_class}::INSTALLED_BROWSER_FILE", File.join(dir, "browser-path"))
    allow(Ferrum::Browser).to receive(:new) do |**options|
      @ferrum_options = options
      instance_double(Ferrum::Browser)
    end
  end

  around do |example|
    original = ENV.delete("BROWSER_PATH")
    example.run
  ensure
    original ? ENV["BROWSER_PATH"] = original : ENV.delete("BROWSER_PATH")
  end

  def browser_path_used(**options)
    described_class.new(logger: messages.method(:push), **options)
    @ferrum_options[:browser_path]
  end

  def install(path) = File.write(described_class::INSTALLED_BROWSER_FILE, "#{path}\n")

  it "prefers the Chromium installed by `script/install-chromium` over system browsers" do
    install(installed)
    expect(browser_path_used).to eq(installed)
    expect(messages).to eq(["Using browser at #{installed}"])
  end

  it "lets --browser-path and BROWSER_PATH override the installed Chromium" do
    install(installed)
    expect(browser_path_used(browser_path: "/opt/chrome")).to eq("/opt/chrome")

    ENV["BROWSER_PATH"] = "/env/chrome"
    expect(browser_path_used).to eq("/env/chrome")
  end

  it "falls back to browser detection when nothing is installed or the install is gone" do
    expect(browser_path_used).to be_nil

    install(File.join(dir, "deleted"))
    expect(browser_path_used).to be_nil
    expect(messages.last).to include("Ignoring missing browser").and include("script/install-chromium")
  end
end
