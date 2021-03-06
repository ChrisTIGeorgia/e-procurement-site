class AlertMailer < ActionMailer::Base
  default from: "alerts@procwatch.com"

  def search_alert(user, search, searchUpdates)
    @search = search
    @updates = searchUpdates
    subject = ""
    if search.searchtype == "supplier"
      subject = "New Supplier Search Update"
    elsif search.searchtype == "procurer"
      subject = "New Procurer Search Update"
    else
      subject = "New Tender Search Update"
    end
    mail(:to => user.email, :subject => "New Search Updates")
  end

  def tender_alert(user, tender, attributes)
    @tender = tender
    @attributes = attributes
    mail(:to => user.email, :subject => "New Tender Updates")
  end

  def data_process_started()
    mail(:to => "Chris@transparency.ge", :subject => "data process started")
  end

  def data_process_finished()
    mail(:to => "Chris@transparency.ge", :subject => "data process finished")
  end

  def meta_started()
    mail(:to => "Chris@transparency.ge", :subject => "meta started")
  end
end
