require "application_system_test_case"

class PagesTest < ApplicationSystemTestCase
  test "gracefully fails on unknown page" do
    assert_raises(ActionController::RoutingError) do
      visit "/pages/not-existing-one"
    end
  end

  test "it only allows html format" do
    assert_raises(ActionController::RoutingError) do
      visit "/pages/data.zip"
    end
  end

  test "renders /pages/about for all supported languages" do
    I18n.available_locales.each do |locale|
      visit "/?locale=#{locale}"
      click_link I18n.t("layouts.application.footer.about")

      assert_text I18n.t("pages.about.title")
    end
  end

  test "renders /pages/download" do
    rubygem = create(:rubygem, name: "rubygems-update")
    create(:version, number: "1.4.8", rubygem: rubygem)
    create(:version,
      number: "3.5.22",
      created_at: Time.zone.local(2024, 10, 16),
      rubygem: rubygem)

    visit "/pages/download"

    assert_text("v3.5.22 - October 16, 2024")
  end

  test "renders /pages/data" do
    visit "/pages/data"

    assert_text("PostgreSQL Data")
  end

  test "renders /pages/security" do
    visit "/pages/security"

    assert_text("Security")
  end

  test "renders /pages/sponsors" do
    visit "/pages/sponsors"

    assert_text("Sponsors")
  end
end
