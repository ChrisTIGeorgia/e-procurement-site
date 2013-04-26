class UserController < ApplicationController
  before_filter :authenticate_user!
  require "query_helpers" 
  
  def index
    @watched_tenders = current_user.watch_tenders

    @savedSearches = current_user.searches
    @cpvGroups = current_user.cpvGroups
    @userID = current_user.id
  end

  def save_search
    newSearch = Search.new
    newSearch.user_id = current_user.id
    newSearch.searchtype = params[:searchtype]
    newSearch.search_string = params[:search_string]
    newSearch.name = params[:name]
    newSearch.count = params[:count]
    newSearch.last_viewed = DateTime.now
    @savedName = params[:name]
    newSearch.save
    @thisSearchString = params[:search_string]
    @searchType = params[:searchtype]
  end


  def remove_search_from_account
    remove_search()
    redirect_to :back
  end

  def remove_search
    if params[:search_id]
      search = Search.find(params[:search_id])
      search.destroy
    else
      searchList = Search.where( :user_id => current_user.id, :searchtype => params[:searchtype], :name => params[:name], :search_string => params[:search_string] )
      searchList.each do |search|
        search.destroy
      end
      @thisSearchString = params[:search_string]
      @searchType = params[:searchtype]
    end
 
  end

  def unsubscribe_search
    @buttonID = params[:buttonID]
    search = Search.find( params[:search_id] )
    search.email_alert = false
    search.save
    @searchID = search.id
  end

  def subscribe_search
    @buttonID = params[:buttonID]
    search = Search.find( params[:search_id] )
    search.email_alert = true
    search.save
    @searchID = search.id
  end


  def add_procurer_watch
  end

  def remove_procurer_watch
  end

  def add_supplier_watch
  end
  
  def remove_supplier_watch
  end

  def add_tender_watch
    watch_item = WatchTender.new
    watch_item.tender_url = params[:tender_url]
    watch_item.user_id = current_user.id
    watch_item.save
    @tenderUrl = params[:tender_url]
    subscribe_tender(watch_item)
  end

  def remove_tender_watch_from_account
    remove_tender_watch()
    redirect_to :back
  end

  def remove_tender_watch
    tenders = WatchTender.where( :tender_url => params[:tender_url], :user_id => current_user.id )
    tenders.each do |watch_tender|
      watch_tender.destroy
    end
    @tenderUrl = params[:tender_url]
  end

  def subscribe_tender( tender_watch = nil )
    
    if tender_watch == nil
      #nothing passed so this must be coming from a view
      tender_watch = WatchTender.find(params[:tender_watch_id])
      @buttonID = params[:buttonID]
      @tender_watch_id = params[:tender_watch_id]
    end

    tender = Tender.where(:url_id => tender_watch.tender_url).first
    tender_watch.email_alert = true
    tender_watch.save
  end

  def unsubscribe_tender
    tender_watch = WatchTender.find(params[:tender_watch_id])
    @buttonID = params[:buttonID]
    @tender_watch_id = params[:tender_watch_id]
    tender_watch.email_alert = false
    tender_watch.save
  end

  def rebuild_search
    if params[:searchtype] == "tender"
      searchParams = QueryHelper.buildSearchParamsFromString(params[:searchString])
      searchParams[:controller] = "tenders"
      searchParams[:action] = "search"
      redirect_to searchParams
    end
  end

  def newCPVGroup
    @userID = params[:user_id]
  end
  
  def sendAlert
    search = Search.find(params[:search_id])
    AlertMailer.search_alert(current_user,search).deliver
  end

  def sendTenderAlert
    tender = Tender.find(params[:tender_id])
    attributes = ["estimated_value", "test", "procurring_entity_id"]
    AlertMailer.tender_alert(current_user,tender,attributes).deliver
  end

  def create_group
    user = User.find(params[:user_id])
    group = CpvGroup.new
    group.user_id = user.id
    group.name = params[:name]
    group.save
  end

  def save_cpv_group
    codes = params[:codes].split(",")
    category = params[:category]
    cpvGroup = CpvGroup.new
    cpvGroup.user_id = params[:user_id]
    cpvGroup.name = category
    
    codes.each do |code|
      cpv = TenderCpvClassifier.where( :cpv_code => code.to_i ).first
      if cpv
        cpvGroup.tender_cpv_classifiers << cpv
      end
    end
    cpvGroup.save
    if cpvGroup.user_id == current_user.id
      redirect_to :action => :index
    else
      redirect_to :controller => :admin, :action =>:manageCPVs
    end
  end

end
