# encoding: utf-8 
class OrganizationsController < ApplicationController
  helper_method :sort_column, :sort_direction
  include GraphHelper 
  include ApplicationHelper
  def search
    @params = params
    name = params[:organization][:name]
    code = params[:organization][:code]
    org_type = params[:org_type]

    translations = nil
    #run the name through an external translator
    if name.length > 0
     translations = findStringTranslations(name)
    end

    name = "%"+name+"%"
    code = "%"+code+"%"
    
    foreignOnly = params[:isForeign][:foreign]

    orgString = ""
    if not org_type == ""
      orgString = " AND org_type = '"+org_type+"'"
    end
    conditions = "is_bidder = true AND code LIKE '"+code +"'"+ orgString
    if foreignOnly == '1'
      conditions += " AND country NOT LIKE 'საქართველო'"
    end
    if translations
      conditions += " AND ( name LIKE '"+name+"'"
      translations.each do |translation|
       conditions += " OR name LIKE '"+"%"+translation+"%"+"'"
      end
      conditions += " )"
    else
      conditions += " AND name LIKE '"+name+"'"
    end
    
    results = Organization.where(conditions)
    @numResults = results.count
    @organizations = results.paginate(:page => params[:page]).order(sort_column + ' ' + sort_direction)

    respond_to do |format|
      format.html
      format.csv {        
        send_data buildCSV(results)
      }
    end 
  end

  def buildCSV( results )
     csv_string = CSV.generate do |csv|
       csv << ["Name","Country","Legal Type","City","Address","Phone Number","Fax Number","Email","Web Page","Code"]
       results.each do |org|
         csv << [org.name,org.country,org.org_type,org.city,org.address,org.phone_number,org.fax_number,org.email,
                 org.webpage,org.code]
       end
    end
    return csv_string   
  end

  def search_procurer
    @params = params
    name = params[:organization][:name]
    code = params[:organization][:code]
    org_type = params[:org_type]

    translations = nil
    #run the name through an external translator
    if name.length > 0
     translations = findStringTranslations(name)
    end

    name = "%"+name+"%"
    code = "%"+code+"%"
    #dirty hack remove this scrape side
    if org_type == "50% მეტი სახ წილ საწარმო"
      org_type = "50% მეტი სახ. წილ. საწარმო"
    end
    orgString = ""
    if not org_type == ""
      orgString = " AND org_type ='"+org_type+"'"
    end
    conditions = "is_procurer = true AND code LIKE '"+code+"'"+ orgString
    if translations
      conditions += " AND ( name LIKE '"+name+"'"
      translations.each do |translation|
       conditions += " OR name LIKE '"+"%"+translation+"%"+"'"
      end
      conditions += " )"
    else
      conditions += " AND name LIKE '"+name+"'"
    end

    results = Organization.where(conditions)
    @numResults = results.count
    @organizations = results.paginate( :page => params[:page]).order(sort_column + ' ' + sort_direction)
    respond_to do |format|
      format.html
      format.csv {        
        send_data buildCSV(results)
      }
    end 
  end

  def show_procurer
    id = params[:id]
    @organization = Organization.find(id)
    tenders = Tender.find_all_by_procurring_entity_id(id)
    @numTenders = tenders.count
    @totalEstimate = 0
    @actualCost = 0
    totalBids = 0
    totalBidders = 0
    @numAgreements = 0

    tendersPerCpv = {}
    @tendersOffered = []
    tenders.each do |tender|
      cpvDescription = TenderCpvClassifier.where(:cpv_code => tender.cpv_code).first.description_english
      if cpvDescription == nil
        cpvDescription = "NA"
      end
      tender[:cpvDescription] = cpvDescription
      @tendersOffered.push(tender)

      if tendersPerCpv[tender.cpv_code]
        tendersPerCpv[tender.cpv_code][1] += 1
      else
        tendersPerCpv[tender.cpv_code] = [cpvDescription, 1 ]
      end
    end

    tendersPerCpv = tendersPerCpv.sort { |a,b| b[1][1] <=> a[1][1]}
    @Cpvs = []
    tendersPerCpv.each do |key, value|
      @Cpvs.push( value )
    end
  
    @successfulTenders = []
    cpvAgreements = {}
    #lets get some aggregate tender stats
    @tendersOffered.each do |tender|    
      agreements = Agreement.find_all_by_tender_id(tender.id)
      #get last agreement
      lastAgreement = nil
      agreements.each do |agreement|
        if not lastAgreement or lastAgreement.amendment_number < agreement.amendment_number
          lastAgreement = agreement
        end
      end
      if lastAgreement
        @actualCost += lastAgreement.amount
        @numAgreements += 1
        @totalEstimate += tender.estimated_value
        @successfulTenders.push( [tender,lastAgreement] )
        item = { :name => tender.cpvDescription, :value => lastAgreement.amount, :code => tender.cpv_code, :children => [] }
        if not cpvAgreements[tender.cpv_code]
          cpvAgreements[tender.cpv_code] = item
        else
          old = cpvAgreements[tender.cpv_code]
          old[:value] += item[:value]
          cpvAgreements[tender.cpv_code] = old
        end
      end

       @successfulTenders = @successfulTenders.sort{ |a,b| a[0].tender_announcement_date <=> b[0].tender_announcement_date }

      #now look at bid stats
      bidders = Bidder.find_all_by_tender_id(tender.id)
      bidders.each do |bidder|
        totalBids += bidder.number_of_bids
      end
      totalBidders += bidders.count
    end


    @jsonString = createTreeGraphStringFromAgreements( cpvAgreements )

    #time for tasty averages
    @averageBids = totalBids.to_f/@numTenders
    @averageBidders = totalBidders.to_f/@numTenders
    @numNoAgreements = @numTenders - @numAgreements
    costString = "N/A"
    if @totalEstimate > 0
      costString = "%.1f" % ((1-@actualCost/@totalEstimate)*100)
    end
    @costVsEstimateSaving = costString
  end
                          
  def download_proc_tenders
    respond_to do |format|
      format.csv{
        tenders = Tender.find_all_by_procurring_entity_id(params[:id])
        send_data buildTenderCSVString(tenders)
      }
    end
  end

  def download_org_tenders
    respond_to do |format|
      format.csv{   
        allBids = Bidder.find_all_by_organization_id(params[:id])
        tenders = []
        allBids.each do |bid|
          tender = Tender.find(bid.tender_id)
          tenders.push(tender)
        end

        send_data buildTenderCSVString(tenders)
      }
    end
  end
  

  def show
    id = params[:id]
    @organization = Organization.find(id)
 
    allAgreements = Agreement.find_all_by_organization_id(id)
    allBids = Bidder.find_all_by_organization_id(id)
    allTenders = []
    @topFiveCpvs = []
    tendersPerCpv = {}
    allBids.each do |bid|
      tender = Tender.find(bid.tender_id)
      allTenders.push(tender)
      if tendersPerCpv[tender.cpv_code]
        tendersPerCpv[tender.cpv_code] += 1
      else
        tendersPerCpv[tender.cpv_code] = 1
      end
    end
    
    tendersPerCpv = tendersPerCpv.sort { |a,b| b[1] <=> a[1]}
    @topFiveCpvs = []
    count = 0
    tendersPerCpv.each do |key, value|
      count = count + 1
      if count > 50
        break
      end
      description = TenderCpvClassifier.where(:cpv_code => key).first.description_english
      @topFiveCpvs.push( [description,value] )
    end 
    

    tendersWon = {}
    #find all tenders we won
    if allAgreements
      allAgreements.each do |agreement|
        agreementTender = tendersWon[agreement.tender_id]
        if not agreementTender
          tendersWon[agreement.tender_id] = [agreement,Tender.find(agreement.tender_id)]
        elsif agreementTender[0].amendment_number < agreement.amendment_number
          tendersWon[agreement.tender_id] = [agreement, agreementTender[1]]
        end
      end
    end

    

    #find all competitors
    @competitors = []
    org_competitors = Competitor.where("organization_id = "+id)
    org_competitors.each do | competitor |
      info = []
      info.push(Organization.find(competitor.rival_org_id))
      info.push(competitor.num_tenders)
      @competitors.push( info )
    end

    @numTenders = allTenders.count
    @numTendersWon = tendersWon.size
    @WLR = @numTendersWon.to_f()/@numTenders.to_f()
    @totalValueOfAllContracts = 0
    @totalEstimatedValueOfContractsWon = 0
    @averageNumBiddersOnContractsWon = 0
    procuringEntities = {}
    tendersWon.each do |key, tender|
      @totalValueOfAllContracts += tender[0].amount
      @totalEstimatedValueOfContractsWon += tender[1].estimated_value
      @averageNumBiddersOnContractsWon += tender[1].bidders.count
      procuringID = tender[1].procurring_entity_id
      if procuringEntities[procuringID]
        procuringEntities[procuringID] += 1
      else
        procuringEntities[procuringID] = 1
      end
    end

    procuringEntities = procuringEntities.sort { |a,b| b[1] <=> a[1]}
    @topTenProcuringEntities = []
    count = 0

    procuringEntities.each do |key, value|
      count = count + 1
      if count > 50
        break
      end
      @topTenProcuringEntities.push( [Organization.find(key), value] )
    end
    if @numTendersWon != 0
      @averageNumBiddersOnContractsWon = @averageNumBiddersOnContractsWon.to_f / @numTendersWon.to_f
      @EstimatedVActual = @totalValueOfAllContracts/ @totalEstimatedValueOfContractsWon
    end

    @tenderInfo = []
    #create a hash with tasty info
    allTenders.each do |tender|
      tenderDuration = (tender.bid_end_date - tender.bid_start_date).to_i
      infoItem = { :id => tender.id, :tenderCode => tender.tender_registration_number, :numBidders => tender.bidders.count, :bidDuration => tenderDuration, :highest_bid => nil, :lowest_bid => nil, :numBids => nil, :start_amount => tender.estimated_value, :won => false, :procurerName => nil, :procurerID => tender.procurring_entity_id, :tenderAnnouncementDate => tender.tender_announcement_date}
      infoItem[:procurerName] = Organization.find(tender.procurring_entity_id).name
      if tendersWon[tender.id]
        infoItem[:won] = true
      end

      allBids.each do |bid|
        if bid.tender_id == tender.id
          infoItem[:highest_bid] = bid.first_bid_amount
          infoItem[:lowest_bid] = bid.last_bid_amount
          infoItem[:numBids] = bid.number_of_bids
          break
        end
      end
      @tenderInfo.push(infoItem)
    end
    @tenderInfo.sort! { |a,b| (a[:won] ? -1 : 1) }
    tendersWon = tendersWon.sort { |a,b| a[1][1].tender_announcement_date <=> b[1][1].tender_announcement_date }

    @simpleTenderStats = {}
    @TenderStats = {}
    tendersWon.each do |key,tenderItem|
      tender = tenderItem[1]
      date = tender.tender_announcement_date.to_time.to_i/86400
      dateStats = @TenderStats
      if tender.tender_type.strip == "გამარტივებული ელექტრონული ტენდერი"
        dateStats = @simpleTenderStats
      end
      if not dateStats[date]
        dateStats[date] = [tender, tenderItem[0].amount]
      else
        #this tender was announced on the same day as another tender and we can only go as far as per day on the graph
        #so lets pick the most important tender and ignore the other one :(
        old = dateStats[date]
        if old[0].estimated_value < tender.estimated_value
          #overwrite old data
          dateStats[date] = [tender, tenderItem[0].amount]
        end
      end
    end
  end

  private

  def sort_column
    params[:sort] || "name"
  end

  def sort_direction
    params[:direction] || "asc"
  end



end
