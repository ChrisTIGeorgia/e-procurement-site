class AggregateController < ApplicationController
  def cpvVsCompany
    companies = {}
    cpvGroup = CpvGroup.find(params[:cpvGroup])
    classifiers = cpvGroup.tender_cpv_classifiers
    cpvAggregates = nil
    sqlString = ''
    #change this to look at cpv type
    if cpvGroup.id == 1
      cpvAggregates = AggregateCpvRevenue.all
    else
      classifiers.each do |classifier|
        sqlString += "cpv_code = "+classifier.cpv_code.to_s+ " OR "
      end
      sqlString = sqlString[0..-4]
    end
    cpvAggregates = AggregateCpvRevenue.where(sqlString)

    cpvAggregates.each do |companyAggregate|
      companyData = companies[companyAggregate.organization_id]
      company = Organization.find(companyAggregate.organization_id)
      if not companyData
        companies[companyAggregate.organization_id] = { :total => companyAggregate.total_value, :company => company }
      else
        companyData[:total] = companyData[:total] + companyAggregate.total_value  
        companies[companyAggregate.organization_id] = companyData
      end
    end


    totalContractValues = []   
    companyArray = []
    companies.each do |index,hash|
      companyArray.push(hash)
    end
    companyArray.sort! { |a,b| (a[:total] > b[:total] ? -1 : 1) }
    @TopTen = []
    count = 1
    companyArray.each do |company|
      @TopTen.push(company)
      count = count + 1
      if count > 10
        break
      end
    end

  end
end
