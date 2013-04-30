module Console::ConsoleHelper

  #FIXME: Replace with real isolation of login state
  def logout_path
    nil
  end

  def outage_notification
  end

  def product_branding
    [
      content_tag(:span, nil, :class => 'brand-image'),
      content_tag(:span, "<strong>Open</strong>Shift Enterprise".html_safe, :class => 'brand-text headline'),
    ].join.html_safe
  end

  def product_title
    'OpenShift Enterprise'
  end
end
