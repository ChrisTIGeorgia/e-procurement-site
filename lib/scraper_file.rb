#!/bin/env ruby
# encoding: utf-8

module ScraperFile

  FILE_TENDER = "tenders.json"
  FILE_ORGANISATIONS = "organisations.json"
  FILE_TENDER_BIDDERS = "tenderBidders.json"
  FILE_TENDER_AGREEMENTS = "tenderAgreements.json"
  FILE_TENDER_DOCUMENTS = "tenderDocumentation.json"
  FILE_TENDER_CPV_CODES = "tenderCPVCode.json"
  FILE_WHITE_LIST = "whiteList.json"
  FILE_BLACK_LIST = "blackList.json"
  FILE_COMPLAINTS = "complaints.json"

  require 'csv'
  require 'json'
  require "query_helper"
  require "translation_helper"
  require "aggregate_helper"
  

  # if we have an oldData set and a newDataset we can generate some info about the differences before merging the sets
  def self.diffData
    #switch all new records dataset id to the live version
    if @numDatasets > 1
      Tender.find_each(:conditions => "dataset_id = "+@newDataset.id.to_s) do |tender|
        tender.dataset_id = @liveDataset.id
      end       
        
      Organization.find_each(:conditions => "dataset_id = "+@newDataset.id.to_s) do |organization|
        organization.dataset_id = @liveDataset.id
      end
    end
  end	


  def self.processTenders

    tender_file_path = "#{Rails.root}/public/system/#{FILE_TENDER}"
    File.open(tender_file_path, "r") do |infile|
      count = 0
      Tender.transaction do
        while(line = infile.gets)
          count = count + 1
          item = JSON.parse(line)
          tender = Tender.new
          # basic tender info
          if count%100 == 0
            puts "tender: #{count}"
          end
          tender.url_id = item["tenderID"]
          tender.dataset_id = @newDataset.id
          tender.tender_type = self.cleanString(item["tenderType"])

          tender.tender_registration_number = item["tenderRegistrationNumber"]
          tender.tender_status = self.cleanString(item["tenderStatus"])
          tender.tender_announcement_date = Date.parse(item["tenderAnnouncementDate"])     
          tender.bid_start_date = Date.parse(item["bidsStartDate"])
          tender.bid_end_date = Date.parse(item["bidsEndDate"])
          tender.estimated_value = item["estimatedValue"]
          tender.cpv_code = item["cpvCode"].split("-")[0]
          tender.addition_info = item["info"]
          tender.units_to_supply = item["amountToSupply"]
          tender.supply_period = item["supplyPeriod"]
          tender.offer_step = item["offerStep"]
          tender.guarantee_amount = item["guaranteeAmount"]
          tender.guarantee_period = item["guaranteePeriod"]
          tender.num_bids = 0
          tender.num_bidders = 0

          organization = Organization.where("organization_url = ? AND dataset_id = ?",item["procuringEntityUrl"],@newDataset.id).first      
          if organization             
            tender.procurring_entity_id = organization.id
            tender.procurer_name = organization.name
        
            if !organization.is_procurer
              organization.is_procurer = true
              organization.save
            end
          end
          #is there an old tender with this url?
          oldTender = nil
          if @numDatasets > 1
            #look at previous scraped data and see if we have the same tender
            oldTender = Tender.where(:url_id => tender.url_id,:dataset_id => @liveDataset.id).first
            if oldTender
              watch_tender = WatchTender.where(:tender_url => tender.url_id).first
              if watch_tender
                differences = oldTender.findTenderDifferences(tender)
                if differences.length > 0
                  #store changed fields in hash
                  hash = ""
                  differences.each do |difference|
                    hash += difference + "#"
                  end
                  watch_tender.hash = hash
                  watch_tender.has_updated = true
                end
              end
            end 
          end         
          tender.save
          @newTenders.push(tender)
          if oldTender
            puts "destroying tender: " + oldTender.id.to_s
            oldTender.destroy
          end 
        end #while
      end#transaction
    end#file
  end #processTenders

  def self.processOrganizations
    org_file_path = "#{Rails.root}/public/system/#{FILE_ORGANISATIONS}"
    File.open(org_file_path, "r") do |infile|
      count = 0
      Organization.transaction do
        while(line = infile.gets)
          count = count + 1
          item = JSON.parse(line)
         
          #don't process if we have already dealt with this org this time
          organization = Organization.where("organization_url = ? AND dataset_id = ?",item["OrgUrl"],@newDataset.id).first
          if !organization
            organization = Organization.new 
            if count%100 == 0
              puts "organization: #{count}"
            end
            organization.dataset_id = @newDataset.id
            organization.organization_url = item["OrgUrl"]
            organization.code = item["OrgID"]
            organization.name = self.cleanString(item["Name"])
            organization.country = self.cleanString(item["Country"])
            organization.org_type = self.cleanString(item["Type"])
            organization.city = self.cleanString(item["city"])
            organization.address = self.cleanString(item["address"])  
            organization.phone_number = item["phoneNumber"]
            organization.fax_number = item["faxNumber"]
            organization.email = self.cleanString(item["email"])
            organization.webpage = self.cleanString(item["webpage"])
            organization.is_procurer = false
            organization.is_bidder = false
            #if we have an old dataset we can check if this org has been updated
            if @numDatasets > 1
              oldOrganization = Organization.where(:organization_url => organization.organization_url, :dataset_id => @liveDataset.id).first
              if oldOrganization
                #this is an org update we could send email alerts here
              end
            end   
            puts "saving org: " + organization.id.to_s       
            organization.save
            @newOrgsTemp.push(organization)
            #now we know everything is sorted we can run a name translation
            self.generateOrganizationNameTranslation( organization )      
          end#if
        end#while
      end#transaction
    end#do
  end#process org


  def self.processBidders
    bidder_file_path = "#{Rails.root}/public/system/#{FILE_TENDER_BIDDERS}" 
    File.open(bidder_file_path, "r") do |infile|
      count = 0
      Bidder.transaction do
        while(line = infile.gets)
          count = count + 1
          item = JSON.parse(line)

          bidder = Bidder.new       
          if count%100 == 0
            puts "bidder: #{count}"
          end
          tender = Tender.where("url_id = ? AND dataset_id = ?",item["tenderID"],@newDataset.id).first
          bidder.tender_id = tender.id
          bidder.organization_url = item["OrgUrl"]
          bidder.first_bid_amount = item["firstBidAmount"]
          begin
            bidder.first_bid_date = Date.parse(item["firstBidDate"])
          rescue
            bidder.first_bid_date = nil         
          end
          bidder.last_bid_amount = item["lastBidAmount"]
          begin
            bidder.last_bid_date = Date.parse(item["lastBidDate"])
          rescue
            bidder.last_bid_date = nil         
          end
          bidder.number_of_bids = item["numberOfBids"]
          tender.num_bids = tender.num_bids + bidder.number_of_bids
          tender.num_bidders = tender.num_bidders + 1
          
          organization = Organization.where("organization_url = ? AND dataset_id = ?",item["OrgUrl"],@newDataset.id).first
          if !organization
            #wtf where is the org?
          else
            bidder.organization_id = organization.id
            if !organization.is_bidder
              organization.is_bidder = true
              organization.save
            end
          end
          bidder.save
          tender.save
        end#while
      end#transaction
    end#file  
  end#processBidders

  def self.processAgreements
    agreement_file_path = "#{Rails.root}/public/system/#{FILE_TENDER_AGREEMENTS}"
    File.open(agreement_file_path, "r") do |infile|
      count = 0
      Agreement.transaction do
        while(line = infile.gets)
          count = count + 1
          item = JSON.parse(line)
          agreement = Agreement.new
          
          if count%100 == 0
            puts "agreement: #{count}"
          end
          tender = Tender.where(["url_id = ? AND dataset_id = ?",item["tenderID"],@newDataset.id]).first
          agreement.tender_id = tender.id
          agreement.amendment_number = item["AmendmentNumber"]
          agreement.documentation_url = item["documentUrl"]
          
          if agreement.documentation_url == "disqualifed" or agreement.documentation_url == "bidder refused agreement"

            puts "disqualifed agreement"
            organization = Organization.where(["name = ? AND dataset_id = ?",item["OrgUrl"].gsub("&amp;","&"),@newDataset.id]).first
            if organization
              agreement.organization_url = organization.organization_url
              agreement.organization_id = organization.id
              agreement.amount = -1
              agreement.currency ="NULL"
              begin
                agreement.start_date = Date.parse(item["StartDate"])
              rescue
                agreement.start_date = "NULL"
              end
              agreement.expiry_date = "NULL"
            end
          else
            puts "normal agreement"
            agreement.organization_url = item["OrgUrl"]
            string_arr = item["Amount"].gsub(/\s+/m, ' ').strip.split(" ")
            agreement.amount = string_arr[0]
            currency = "NONE"
            if string_arr[1]
              currency = string_arr[1]
            end
            agreement.currency = currency
            begin
              agreement.start_date = Date.parse(item["StartDate"])
            rescue
              agreement.start_date = "NULL"
            end
            begin
              agreement.expiry_date = Date.parse(item["ExpiryDate"])
            rescue
              agreement.expiry_date = "NULL"
            end

            #The organisation that won this contract should have bid so it should have already been created
            #so lets check the organisation database and cross-reference the org-url to get the org-id
            organization = Organization.where(["organization_url = ? AND dataset_id = ?",item["OrgUrl"],@newDataset.id]).first
            if !organization
              #wtf where is the org?
            else
              agreement.organization_id = organization.id
            end
                  
            agreement.save
          end
        end#while
      end#transaction
    end#file
  end#processAgreements

  def self.processCPVCodes
    cpv_file_path = "#{Rails.root}/public/system/#{FILE_TENDER_CPV_CODES}"
    File.open(cpv_file_path, "r") do |infile|
      count = 0
      TenderCpvCode.transaction do
        while(line = infile.gets)
          count = count + 1
          item = JSON.parse(line)  
       
          cpvCode = TenderCpvCode.new       
          tender = Tender.where("url_id = ? AND dataset_id = ?",item["tenderID"],@newDataset.id).first
          cpvCode.tender_id = tender.id
          cpvCode.cpv_code = item["cpvCode"]
          cpvCode.description = item["description"]
          if count%100 == 0
            puts "cpvCode: #{count}"
          end
          cpvCode.save
        end#while
      end#transaction
    end#file 
  end

  def self.processDocuments
    document_file_path = "#{Rails.root}/public/system/#{FILE_TENDER_DOCUMENTS}"
     File.open(document_file_path, "r") do |infile|
      count = 0
      Document.transaction do
        while(line = infile.gets)
          count = count + 1
          item = JSON.parse(line)         
          document = Document.new     
          tender = Tender.where("url_id = ? AND dataset_id = ?",item["tenderID"],@newDataset.id).first
          document.tender_id = tender.id
          document.document_url = item["documentUrl"]
          document.title = item["title"]
          document.author = item["author"]
          document.date = Date.parse(item["date"])
          
          if count%100 == 0
            puts "document: #{count}"
          end

          #if this an update to an old doc
          #remove old doc
          oldDoc = Document.where(:document_url => document.document_url).first
          if oldDoc
            oldDoc.destroy
          end
          document.save
        end#while
      end#transaction
    end #file
  end #processDocuments

  #go through all tenders and find all unqiue cpv codes
  def self.createCPVCodes
    #load the cpv codes from file
    csv_text = File.read("lib/data/cpv_data.csv")
    csv = CSV.parse(csv_text)

    #change this to make a full list via scraped data
    subCodes = TenderCpvCode.find(:all, :select => 'distinct cpv_code, description')
    tenders = Tender.find(:all, :select =>'distinct cpv_code')
      
    tenders.each do |tender|
      if tender.cpv_code
        oldCode = TenderCpvClassifier.where(:cpv_code => tender.cpv_code).first
        if not oldCode
          code = TenderCpvClassifier.new
          data = tender.cpv_code.split("-")        
          code.cpv_code = data[0]
          code.description = data[1]
          intCode = code.cpv_code.to_i          
          csv.each do |pair|
            if pair[0].to_i == intCode
              code.description_english = pair[1]
              break
            end
          end#for each pair
          code.save
        end#if this is a new cpv_code
      end#if tender has cpv_code
    end#tenders

    subCodes.each do |subCode|
      oldCode = TenderCpvClassifier.where(:cpv_code => subCode.cpv_code).first
      if oldCode
        if oldCode.description == nil
          oldCode.description = subCode.description
          oldCode.save
        end
      else
        code = TenderCpvClassifier.new       
        code.cpv_code = subCode.cpv_code
        code.description = subCode.description
        intCode = code.cpv_code.to_i          
        csv.each do |pair|
          if code.cpv_code.to_i == intCode
            code.description_english = pair[1]
            break
          end
        end#for each pair
        code.save
      end#else
    end#each cpv
      
  end#createcpv


  def self.georgianToDate( dateString )
    elements = dateString.split()
    month = elements[1]
    monthInt = -1

    case month
    when "იანვარი"
      monthInt = "1"
    when "თებერვალი"
      monthInt = "2"
    when "მარტი"
      monthInt = "3"
    when "აპრილი"
      monthInt = "4"
    when "მაისი"
      monthInt = "5"
    when "ივნისი"
      monthInt = "6"
    when "ივლისი"
      monthInt = "7"
    when "აგვისტო"
      monthInt = "8"
    when "სექტემბერი"
      monthInt = "9"
    when "ოქტომბერი"
      monthInt = "10"
    when "ნოემბერი"
      monthInt = "11"
    when "დეკემბერი"
      monthInt = "12"
    end

    monthString = elements[2]+"/"+monthInt+"/"+elements[0]
    return Date.parse(monthString)
  end

  def self.processWhiteList
    white_list_file_path = "#{Rails.root}/public/system/#{FILE_WHITE_LIST}"
    File.open(white_list_file_path, "r") do |infile|
      WhiteListItem.transaction do
        WhiteListItem.delete_all
        while(line = infile.gets)
          item = JSON.parse(line)         
          whiteListItem = WhiteListItem.new
          whiteListItem.organization_id = nil
          org = Organization.where("code = ?",item["orgID"]).first 
          if org
            whiteListItem.organization_id = org.id
            org.bw_list_flag = "W"
            org.save
          end
          whiteListItem.organization_name = self.cleanString(item["orgName"])
          whiteListItem.issue_date = self.georgianToDate(item["issueDate"])
          whiteListItem.agreement_url = self.cleanString(item["agreementUrl"])
          whiteListItem.company_info_url = self.cleanString(item["companyInfoUrl"])
          whiteListItem.save
        end
      end
    end
  end

  def self.processBlackList
    black_list_file_path = "#{Rails.root}/public/system/#{FILE_BLACK_LIST}"
    File.open(black_list_file_path, "r") do |infile|
      BlackListItem.transaction do
        BlackListItem.delete_all
        while(line = infile.gets)
          item = JSON.parse(line)
          blackListItem = BlackListItem.new
          blackListItem.organization_id = nil
          org = Organization.where("code = ?",item["orgID"]).first
          if org
            blackListItem.organization_id = org.id
            org.bw_list_flag = "B"
            org.save
          end
          blackListItem.organization_name = self.cleanString(item["orgName"])
          blackListItem.issue_date = self.georgianToDate(item["issueDate"])
          blackListItem.procurer_id = nil
          procurer_name = self.cleanString(item["procurer"])
          org = Organization.where("name = ?",procurer_name).first
          if org
            blackListItem.procurer_id = org.id
          end
          blackListItem.procurer_name  = procurer_name
          blackListItem.tender_id = item["tenderID"]
          blackListItem.tender_number = item["tenderNum"]
          blackListItem.reason = item["reason"]
          blackListItem.save
        end
      end
    end
  end

  def self.processComplaints
    complaints_file_path = "#{Rails.root}/public/system/#{FILE_COMPLAINTS}"
    File.open(complaints_file_path, "r") do |infile|
      Complaint.transaction do
       Complaint.delete_all
       while(line = infile.gets)
          item = JSON.parse(line)
          complaintItem = Complaint.new
          complaintItem.organization_id = nil
          org = Organization.where("code = ?",item["orgID"]).first
          if org
            complaintItem.organization_id = org.id
          end
          complaintItem.status = self.cleanString(item["status"])
          complaintItem.tender_id = nil
          tender = Tender.where("tender_registration_number = ?", item["tenderID"]).first
          if tender
            complaintItem.tender_id = tender.id
          end
          complaintItem.complaint = self.cleanString(item["complaint"])
          complaintItem.legal_basis = self.cleanString(item["legalBasis"])
          complaintItem.demand = self.cleanString(item["demand"])
          complaintItem.save
        end     
      end
    end
  end

  def self.storeTenderContractValues
    count = 0
    Tender.find_each do |tender|
      count = count + 1
      if count%100 == 0
        puts "Contract Store "+count.to_s
      end
      agreements = Agreement.find_all_by_tender_id(tender.id)
      #get last agreement
      lastAgreement = nil
      agreements.each do |agreement|
        if not lastAgreement or lastAgreement.amendment_number < agreement.amendment_number
          lastAgreement = agreement
        end
      end
      if lastAgreement
        tender.contract_value = lastAgreement.amount
        tender.winning_org_id = lastAgreement.organization_id
        tender.supplier_name = Organization.find(tender.winning_org_id).name
        tender.save
      end
    end
  end

    def self.storeOrgMeta
     Organization.find_each do |org|
      #get total revenue
      revenues = AggregateCpvRevenue.where(:organization_id => org.id)
      total = 0
      revenues.each do |revenue|
        total += revenue.total_value
      end
      org.total_won_contract_value = total

      #get number of tenders bid on
      org.total_bid_tenders = Bidder.where(:organization_id => org.id).count
      #get number of tenders won
      org.total_won_tenders = Tender.where(:winning_org_id => org.id).count
    
      tenders_offered = Tender.where(:procurring_entity_id => org.id)
      org.total_offered_tenders = tenders_offered.count
      total_offered = 0
      successful_offered = 0
      tenders_offered.each do |offered|
        if offered.contract_value and offered.contract_value >= 0
          total_offered += offered.contract_value
          successful_offered += 1
        end
      end
      
      org.total_offered_contract_value = total_offered
      org.total_success_tenders = successful_offered
      org.save
    end
  end


  def self.processAggregateData
    #for each CPV code calculate the revenue generated for each company and store these entries in the database
    #this way when aggregate data is requested instead of running this expensive process everytime we can just look up the pre-calculated entries in the db.
    AggregateCpvRevenue.delete_all
    ProcurerCpvRevenue.delete_all
    classifiers = TenderCpvClassifier.find(:all)
    classifiers.each do |classifier|
      puts classifier.cpv_code
      Tender.find_each(:conditions => "cpv_code = " + classifier.cpv_code) do |tender|
        if tender.contract_value and tender.contract_value > 0
          tenderValue = tender.contract_value
          company = Organization.find(tender.winning_org_id)
          if company
            aggregateData = AggregateCpvRevenue.where(:cpv_code => classifier.cpv_code, :organization_id => company.id).first
            if not aggregateData
              aggregateData = AggregateCpvRevenue.new
              aggregateData.organization_id = company.id
              aggregateData.cpv_code = classifier.cpv_code
              aggregateData.total_value = tenderValue
            else
              aggregateData.total_value = aggregateData.total_value + tenderValue
            end
            aggregateData.save
          end

          procurer = Organization.find(tender.procurring_entity_id)
          if procurer
            aggregateData = ProcurerCpvRevenue.where(:cpv_code => classifier.cpv_code, :organization_id => procurer.id).first
            if not aggregateData
              aggregateData = ProcurerCpvRevenue.new
              aggregateData.organization_id = procurer.id
              aggregateData.cpv_code = classifier.cpv_code
              aggregateData.total_value = tenderValue
            else
              aggregateData.total_value = aggregateData.total_value + tenderValue
            end
            aggregateData.save
          end
        end
      end
    end
    
    #store data for yearly stats
    AggregateHelper.generateAndStoreAggregateData
  end#process aggregate data

  def self.createUsers
    #NEEDS TO BE REMOVED LATER
    myAdminAccount = User.where(:id => 1).first
    if not myAdminAccount
      myAdminAccount = User.create!({:email => "chris@transparency.ge", :role => "admin", :password => "password84", :password_confirmation => "password84" })
      myAdminAccount.save
    end

    #Get special profile account cpv groups
    profileAccount = User.where( :role => "profile" ).first
    if not profileAccount
      profileAccount = User.create!({:email => "profile@transparency.ge", :role => "profile", :password => "67V9vP7647VVw14", :password_confirmation => "67V9vP7647VVw14" })
      #create special cpv group
      allGroup = CpvGroup.new
      allGroup.id = 1
      allGroup.user_id = profileAccount.id
      allGroup.name = "All"
      allGroup.save
    end


    #create risky special cpv group
    if not CpvGroup.where( :id => 2).first
      risky = CpvGroup.new
      risky.id = 2
      risky.user_id = profileAccount.id
      risky.name = "Risky"
      risky.save
    end
  end

  #take a string  and remove special characters and whitespace
  def self.cleanString( string )
    string = string.gsub(",,","")
    string = string.gsub("„","")
    string = string.gsub("”","")
    string = string.gsub('"',"")
    string = string.gsub("“",'')
    string = string.gsub("&amp;","&")
    string = string.gsub("<br>","\n")
    string = string.gsub("<span>"," ")
    string = string.strip
    return string		
  end

  def self.generateRiskFactors
    #this is all done manually

    holidayIndicator = CorruptionIndicator.where(:id => 1).first
    if not holidayIndicator
      holidayIndicator = CorruptionIndicator.new
      holidayIndicator.name = "Holiday Procurement"
      holidayIndicator.id = 1     
      holidayIndicator.weight = 5
      holidayIndicator.description = "This tender was announced during the holiday period which seems like a strange time to start procurements"
      #holidayIndicator.save
    end

    compeitionIndicator = CorruptionIndicator.where(:id => 2).first
    if not compeitionIndicator
      compeitionIndicator = CorruptionIndicator.new
      compeitionIndicator.name = "Low Competition"
      compeitionIndicator.id = 2     
      compeitionIndicator.weight = 1
      compeitionIndicator.description = "This tender only had 1 bidder while this is quite common in Georgia this could have be caused by a number of corrupt factors"
      compeitionIndicator.save
    end

    biddingIndicator = CorruptionIndicator.where(:id => 3).first
    if not biddingIndicator
      biddingIndicator = CorruptionIndicator.new
      biddingIndicator.name = "Low Price Decrease"
      biddingIndicator.id = 3     
      biddingIndicator.weight = 3
      biddingIndicator.description = "When two or more companies are bidding for a contract it is expected that a bidding war should lower the price a reasonble amount this has not happened in this case"
      biddingIndicator.save
    end

    cpvRiskIndicator = CorruptionIndicator.where(:id => 4).first
    if not cpvRiskIndicator
      cpvRiskIndicator = CorruptionIndicator.new
      cpvRiskIndicator.name = "Risky Contract Type"
      cpvRiskIndicator.id = 4     
      cpvRiskIndicator.weight = 1
      cpvRiskIndicator.description = "This contract has been identified as being in a procurement area that is at higher risk of corruption"
      cpvRiskIndicator.save
    end

    majorPlayerIndicator = CorruptionIndicator.where(:id => 5).first
    if not majorPlayerIndicator
      majorPlayerIndicator = CorruptionIndicator.new
      majorPlayerIndicator.name = "Major players not competiting"
      majorPlayerIndicator.id = 5     
      majorPlayerIndicator.weight = 2
      majorPlayerIndicator.description = "Only one major player has been a bid on this contract"
      #majorPlayerIndicator.save
    end

    contractAmendmentIndicator = CorruptionIndicator.where(:id => 6).first
    if not contractAmendmentIndicator
      contractAmendmentIndicator = CorruptionIndicator.new
      contractAmendmentIndicator.name = "Amendment price is above the price that of a losing bidder"
      contractAmendmentIndicator.id = 6     
      contractAmendmentIndicator.weight = 2
      contractAmendmentIndicator.description = "The winner of this tender has signed an agreement or amendment that has increase the tender price above that of a bid made by a competitor."
      contractAmendmentIndicator.save
    end

    blackListedSupplierIndicatior = CorruptionIndicator.where(:id => 7).first
    if not blackListedSupplierIndicatior
      blackListedSupplierIndicatior = CorruptionIndicator.new
      blackListedSupplierIndicatior.name = "A Blacklisted Company Won the Tender"
      blackListedSupplierIndicatior.id = 7     
      blackListedSupplierIndicatior.weight = 5
      blackListedSupplierIndicatior.description = "The winner of this tender has been placed on the blacklist"
      blackListedSupplierIndicatior.save
    end

    @totalIndicator = CorruptionIndicator.where(:id => 100).first
    if not @totalIndicator
      @totalIndicator = CorruptionIndicator.new
      @totalIndicator.name = "Total risk score"
      @totalIndicator.id = 100
      @totalIndicator.weight = 0
      @totalIndicator.description = "This is the total risk assessement score for this tender"
      @totalIndicator.save
    end

    #remove old flags
    TenderCorruptionFlag.delete_all
    
    #puts "holiday"
    #self.identifyHolidayPeriodTenders(holidayIndicator)   
    puts "competition"
    self.competitionAssessment(compeitionIndicator)
    puts "bidding"
    self.biddingWarAssessment(biddingIndicator)
    puts "risky codes"
    self.identifyRiskyCPVCodes(cpvRiskIndicator)
    #puts "Major players"
    #self.majorPlayerCompetitionAssessment(majorPlayerIndicator)
    puts "amendment"
    self.contractAmendmentAssessment(contractAmendmentIndicator)
    puts "black list"
    self.blackListedSupplierIndicatior

    puts "storing risk indicators on tenders"
    self.addRiskIndicatorsToTenders
  end

  def self.addToRiskTotal( tender, val )
    totalScore = TenderCorruptionFlag.where(:corruption_indicator_id => 100,:tender_id => tender.id ).first
    if not totalScore
      totalScore = TenderCorruptionFlag.new
      totalScore.tender_id = tender.id
      totalScore.corruption_indicator_id = @totalIndicator.id
      totalScore.value = val
    else
      totalScore.value = totalScore.value + val
    end
    totalScore.save
  end

  def self.addRiskIndicatorsToTenders()
    Tender.find_each do |tender|
      flags = TenderCorruptionFlag.where(:tender_id => tender.id)
      flagStr = nil
      flags.each do |flag|
        if flag.corruption_indicator_id < 100
          if not flagStr
            flagStr = flag.corruption_indicator_id.to_s
          else
            flagStr += "#"+flag.corruption_indicator_id.to_s
          end
        end
      end
      tender.risk_indicators = flagStr
      tender.save
    end
  end

  def self.identifyHolidayPeriodTenders(indicator)
    sql = ""
    for year in (2010..Time.now.year)
      conjuction = " OR "
      if year == 2010
        conjuction = ""
      end
      sql = sql + conjuction
      holidayStart = Date.new(year,12,30).to_s
      holidayEnd = Date.new(year+1,1,11).to_s

      sql = sql + "(tender_announcement_date BETWEEN '"+holidayStart+"' AND '"+holidayEnd+"')"
    end

    Tender.find_each(:conditions => sql) do |tender|
      corruptionFlag = TenderCorruptionFlag.new
      corruptionFlag.tender_id = tender.id
      corruptionFlag.corruption_indicator_id = indicator.id
      corruptionFlag.value = 1 # maybe certain dates within this are even worse?
      corruptionFlag.save
      self.addToRiskTotal(tender, (corruptionFlag.value*indicator.weight))
    end
  end
  
  def self.competitionAssessment(indicator)
    Tender.find_each(:conditions => "num_bidders = 1") do |tender|
      corruptionFlag = TenderCorruptionFlag.new
      corruptionFlag.tender_id = tender.id
      corruptionFlag.corruption_indicator_id = indicator.id
      corruptionFlag.value = 1
      corruptionFlag.save
      self.addToRiskTotal(tender, (corruptionFlag.value*indicator.weight))
    end
  end

  def self.biddingWarAssessment(indicator)
    #get all tenders that had a bidding war
    Tender.find_each(:conditions => "num_bidders > 1") do |tender|
      #now check the lowest bid and compare this to the estimated value
      lowestBid = nil
      tender.bidders.each do |bidder|
        if not lowestBid or lowestBid > bidder.last_bid_amount
          lowestBid = bidder.last_bid_amount
        end
        if lowestBid                       
          savingsPercentage = 1 - lowestBid/tender.estimated_value
          if savingsPercentage <= 0.02
            #risky tender!
            corruptionFlag = TenderCorruptionFlag.new
            corruptionFlag.tender_id = tender.id
            corruptionFlag.corruption_indicator_id = indicator.id
            corruptionFlag.value = 1 #could have more for %1 and %0.5 etc
            corruptionFlag.save
            self.addToRiskTotal(tender, (corruptionFlag.value*indicator.weight))
          end
        end
      end
    end
  end

  def self.identifyRiskyCPVCodes(indicator)
    riskyGroup = CpvGroup.find(2)
    classifiers = riskyGroup.tender_cpv_classifiers
    if classifiers.length > 0
      sql = ""
      conjuction = ""
      classifiers.each do |cpv|
        sql = sql + conjuction + "cpv_code = " + cpv.cpv_code.to_s
        conjuction = " OR "
      end

      Tender.find_each(:conditions => sql) do |tender|
        corruptionFlag = TenderCorruptionFlag.new
        corruptionFlag.tender_id = tender.id
        corruptionFlag.corruption_indicator_id = indicator.id
        corruptionFlag.value = 1 #perhaps we could add different values for different codes
        corruptionFlag.save
        self.addRiskIndicatorToTender(tender, indicator.id)
        self.addToRiskTotal( tender, (corruptionFlag.value*indicator.weight)  )
      end
    end
  end


  def self.contractAmendmentAssessment(indicator)
    Tender.find_each(:conditions => "num_bidders > 1") do |tender|
      #look at the latest agreement and check the price vs other bidders
      if tender.contract_value and tender.contract_value > 0
        #needs atleast 1 amendment
        if tender.agreements.count > 1
          winningBidder = nil
          tender.bidders.each do |bidder|
            if bidder.organization_id == tender.winning_org_id
              winningBidder = bidder
              break
            end
          end

          if winningBidder
            tender.bidders.each do |bidder|
              #if another bidders price was lower than an amended price
              if bidder.organization_id != tender.winning_org_id
                if bidder.last_bid_amount > winningBidder.last_bid_amount and bidder.last_bid_amount < tender.contract_value
                  #risky tender!
                  corruptionFlag = TenderCorruptionFlag.new
                  corruptionFlag.tender_id = tender.id
                  corruptionFlag.corruption_indicator_id = indicator.id
                  corruptionFlag.value = 1
                  corruptionFlag.save
                  self.addRiskIndicatorToTender(tender, indicator.id)
                  self.addToRiskTotal( tender, (corruptionFlag.value*indicator.weight)  )
                  break
                end
              end
            end
          end
        end
      end
    end
  end


  #tough one
  def self.majorPlayerCompetitionAssessment(indicator)
    puts "not done"
  end

  def self.blacklistSupplierAssessment(indicator)
    blackListedOrgs = BlackListItems.select(:organization_id)
    Tender.find_each do |tender|
      if blackListedOrgs.include?(tender.winning_org_id)
        #risky tender!
        corruptionFlag = TenderCorruptionFlag.new
        corruptionFlag.corruption_indicator_id = indicator.id
        corruptionFlag.value = 1
        corruptionFlag.save
        self.addRiskIndicatorToTender(tender, indicator.id)
        self.addToRiskTotal( tender, (corruptionFlag.value*indicator.weight)  )
      end
    end
  end


  def self.generateCompetitorData()

    #puts "begin cpv output"
    orgs = {}
    #nodeID = 0
    #edgeID = 0
    Tender.find_each do |tender|
      ids = []
      winning_org_id = tender.winning_org_id
      if winning_org_id
        tender.bidders.each do |bidder|
          ids.push(bidder.organization_id)
        end
        puts "Processing tender: " + tender.id.to_s
        if not orgs[winning_org_id]
          nodeID+=1
          newOrg = Organization.find(winning_org_id)
          orgs[winning_org_id] = [newOrg, nodeID,{}]        
        end
        ids.each do |competitor_id|
          if not competitor_id == winning_org_id
            if not orgs[competitor_id]
              nodeID+=1
              newOrg = Organization.find(competitor_id)
              orgs[competitor_id] = [newOrg, nodeID,{}]
            end         
            #create link
            if not orgs[winning_org_id][2][nodeID]
              orgs[winning_org_id][2][nodeID] = 0
            end
            orgs[winning_org_id][2][nodeID] += 1          
          end#if not same org
        end#for all orgs
      end
    end#for all tenders
    

=begin    File.open("nodes.csv", "w+") do |nf|
      nf.write("Id,Label\n")
      File.open("edges.csv", "w+") do |ef|
        ef.write("Source,Target,Type,Id,Label,Weight\n")
        orgs.each do |id,data|
          name = data[0].name
          id = data[1]
          nf.write(id.to_s+","+name+"\n")
          data[2].each do |competitorID, value|
            edgeID+=1
            ef.write( competitorID.to_s+","+id.to_s+",Undirected,"+edgeID.to_s+","+","+value.to_s+"\n")
          end
        end
      end
    end
    puts "cpv saved"
=end
  end

  def self.findCompetitors
    #Competitor.delete_all
    #this is going to take some memory
    companies = {}
    Tender.find_each do |tender|
      ids = []
      tender.bidders.each do |bidder|
        ids.push(bidder.organization_id)
      end
      ids.each do |org_id|
        if not companies[org_id]
          companies[org_id] = {}
        end
        ids.each do |competitor_id|
          if not competitor_id == org_id
            count = companies[org_id][competitor_id]
            if not count
              count = 0
            end
            count = count + 1
            companies[org_id][competitor_id] = count
          end#if not same org
        end#for all competitor ids
      end#for all orgs
    end#for all tenders

    def self.competitorSort(a,b)
      if a[1] < b[1]
        return 1
      else
        return -1
      end
    end

    # we now have a list of companies each with a list of companies they have competed with
    # go through each company find its top 3 competitors and store this in the db
    companies.each do |org_id, competitors|
      competitors = competitors.sort {|a,b| self.competitorSort(a,b) }
      #store top 3
      count = 0
      competitors.each do |competitor_id, value|
        count = count + 1
        if value < 2 or count > 3
          break
        end
        db_competitor = Competitor.new
        db_competitor.organization_id = org_id
        db_competitor.rival_org_id = competitor_id
        db_competitor.num_tenders = value
        db_competitor.save
      end
    end
  end


  def self.sendTenderAlertMail
    #go through all saved Tenders and alert users to changes
    WatchTender.all.each do |watch_tender|
      #check to see if there are any updates
      if watch_tender.has_updated
        attributes = watch_tender.hash.split("#")
        tender = Tender.where(:url_id => watch_tender.tender_url).first
        #a change has been detected send an alert email
        user = User.find(watch_tender.user_id)
        AlertMailer.tender_alert(user, tender, attributes).deliver
      end
    end
  end

  def self.sendSearchAlertMail
    Search.all.each do |search|
      #rerun search and check for new tenders
      queryParams = nil
      query = nil
      updateList = nil
      results = nil
      if search.searchtype == "tender"
        queryParams = QueryHelper.buildTenderSearchParamsFromString(search.search_string)
        data = QueryHelper.buildTenderQueryData(queryParams)
        results = QueryHelper.buildTenderSearchQuery(data)
        updateList = @newTenders
      elsif search.searchtype == "supplier"
        queryParams = QueryHelper.buildSupplierSearchParamsFromString(search.search_string)
        results = QueryHelper.buildSupplierSearchQuery(queryParams)
        updateList = @newSuppliers
      else
        queryParams = QueryHelper.buildProcurerSearchParamsFromString(search.search_string)
        results = QueryHelper.buildProcurerSearchQuery(queryParams)
        updateList = @newProcurers
      end

      searchUpdates = []
      results.each do |result|
        if updateList.include?(result)
          searchUpdates.push(result)
        end
      end
      if searchUpdates.length > 0
        user = User.find(search.user_id)
        search.has_updated = true
        search.save
        if search.email_alert
          AlertMailer.search_alert(user, search, searchUpdates).deliver
        end
      end
    end
  end

  def self.generateOrganizationNameTranslation( organization )
=begin    orgName = organization.name
    puts "translating: " + orgName
    translations = TranslationHelper.findStringTranslations(orgName)
    organization.saveTranslations(translations)
    tenderList = Tender.where(:procurring_entity_id => organization.id)
    tenderList.each do |tender|
      tender.procurer_name += "#"+organization.translation
      tender.save
    end
    tenderList = Tender.where(:winning_org_id => organization.id)
    tenderList.each do |tender|
      tender.supplier_name += "#"+organization.translation
      tender.save
    end
=end
  end


  def self.outputOrgRevenue
    file_path = "#{Rails.root}/public/system/numbers.txt"
    orgs = {}
    File.open(file_path, "r") do |infile|
      while(line = infile.gets)
        orgCode = line.strip()
        org = Organization.where(:code => orgCode).first
        if org and org.total_won_contract_value > 0
          orgs[org.id] = org
        end
      end
    end

    orgs = orgs.sort{ |x, y| y[1][:total_won_contract_value] <=> x[1][:total_won_contract_value] }

    csv_data = CSV.generate() do |csv|
      csv << ["Name","Code","Revenue"]
      orgs.each do |index,org|
       csv << [org.name,org.code,org.total_won_contract_value]
      end
    end
    File.open("app/assets/data/revenues.csv", "w+") do |file|
      file.write(csv_data)
    end
  end

  def buildOrganizationXmlStrings
    xmlString = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
    procurers = Organization.where(:is_procurer => true)
    xmlString += "\n"+'<procurers style="MEDIUM">'
    procurers.each do |proc|
      name = proc.name
      name.delete!('"')
      name.delete!("'")
      name.gsub!("&", "&amp;")
      xmlString += "\n"+'<Name>'+name+'</Name>'
    end
    xmlString += "\n"+'</procurers>'
    File.open("app/assets/data/procurers.xml", "w+") do |file|
      file.write(xmlString)
    end

    xmlString = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>'
    suppliers = Organization.where(:is_bidder => true)
    xmlString += "\n"+'<suppliers style="MEDIUM">'
    suppliers.each do |supplier|
      name = supplier.name
      name.delete!('"')
      name.delete!("'")
      name.gsub!("&", "&amp;")
      xmlString += "\n"+'<Name>'+name+'</Name>'
    end
    xmlString += "\n"+'</suppliers>'
    File.open("app/assets/data/suppliers.xml", "w+") do |file|
      file.write(xmlString)
    end
  end

  def self.process
    start = Time.now
    I18n.locale = :en # do this so formating of floats and dates is correct when reading in json
    @newTenders = []
    @newSuppliers = []
    @newProcurers = []
    @newOrgsTemp = []

    #parse orgs first so that other objects can sort out relationships
    puts "processing Orgs"
    self.processOrganizations
    puts "processing tenders"  
    self.processTenders
    puts "processing bidders"
    self.processBidders
    puts "processing agreements"
    self.processAgreements
    puts "processing docs"
    self.processDocuments
    puts "processing sub cpv codes"
    self.processCPVCodes
    
    puts "processing white list"
    self.processWhiteList
    puts "processing black list"
    self.processBlackList
    puts "process complaints"    
    self.processComplaints

    @newOrgsTemp.each do |org|
      if org.is_bidder
        @newSuppliers.push(org)
      end
      if org.is_procurer
        @newProcurers.push(org)
      end
    end
  end

  def self.generateMetaData
    puts "setting up users"
    self.createUsers
    puts "storing tender results"
    self.storeTenderContractValues

    puts "generating aggregate data"
    self.processAggregateData
    puts "storing org meta"
    self.storeOrgMeta

    puts "finding competitors"
    self.findCompetitors
    puts "finding corruption"
    self.generateRiskFactors

    #self.buildOrganizationXmlStrings
  end

  def self.generateAlerts
    puts "sending tender watch alerts"
    self.sendTenderAlertMail
    puts "sending tender search alerts"
    self.sendSearchAlertMail
  end

  def self.processFullScrape   
    @numDatasets = Dataset.find(:all).count
    @liveDataset = nil
    @newDataset = nil
    #if we have 1 dataset already lets create a new one to hold the new data
    if @numDatasets == 1
      @liveDataset = Dataset.find(1)
      @newDataset = Dataset.new
      #this won't be live until we do our diff
      @newDataset.is_live = false
      @newDataset.save
    elsif @numDatasets > 1
      #if we already have 2 datasets lets use the second dataset as our temp storage id
      @liveDataset = Dataset.find(1)
      @newDataset = Dataset.find(2)
    else
      #we don't have any datasets this is a clean database so lets create the primary dataset and make it live
      @newDataset = Dataset.new
      @newDataset.is_live = true
      @newDataset.save
      @liveDataset = @newDataset
    end

    puts "processing json"
    self.process
    puts "diffing"
    self.diffData
    self.generateMetaData
  end

  def self.processIncrementalScrape
    #self.processWhiteList
    #self.processBlackList
    #self.processComplaints
    self.outputOrgRevenue

    #get current dataset
   # @dataset = Dataset.last
    #AlertMailer.data_process_started().deliver
    #self.process
    #AlertMailer.meta_started().deliver
    #self.generateMetaData
    #self.generateAlerts
    #AlertMailer.data_process_finished().deliver
  end

  def self.buildUserDataOnly
    self.generateCompetitorData
  end

end

