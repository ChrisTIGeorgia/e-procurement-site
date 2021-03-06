# encoding: utf-8 
module QueryHelper 
  def self.dropZeros( string )
    digits = self.countZeros(string)
    return string[0, string.length-digits]
  end

  def self.countZeros( string )
    count = 0
    pos = string.length
    while pos > 0
      if string[pos-1] == '0'
        count = count +1
      else
        break
      end
      pos = pos - 1
    end
    return count
  end

  def self.buildTenderQueryData( data )
    reg_num = data[:tender_registration_number]
    status = data[:tender_status]
    cpvGroupID = data[:cpvGroup]
    keywords = data[:keyword]
    tender_type = data[:tender_type]

    reg_num = "%"+reg_num.gsub('%','')+"%"
    status = "%"+status.gsub('%','')+"%"

    startDate = ""
    endDate = ""
    if data[:announced_after] != ""
      strDate = data[:announced_after].gsub('/','-')
      startDate = Date.strptime(strDate,'%Y-%m-%d')
    end

    if data[:announced_before] != ""
      strDate = data[:announced_before].gsub('/','-')
      endDate = Date.strptime(strDate,'%Y-%m-%d')
    end

    minVal = data[:min_estimate]
    maxVal = data[:max_estimate]

    minBids = data[:min_num_bids]
    maxBids = data[:max_num_bids]
    
    minBidders = data[:min_num_bidders]
    maxBidders = data[:max_num_bidders]

    procurer = "%"+data[:procurer_name]+"%"
    supplier = "%"+data[:supplier_name]+"%"

    translated_status =  "%%"
    status = status.gsub('%','')
    if not status == ""
      translated_status = I18n.t(status, :locale => :ka)
    end
    queryData = {
                 :keywords => keywords, 
                 :cpvGroupID => cpvGroupID.to_s,
                 :tender_registration_number => reg_num.to_s,
                 :tender_status => translated_status,
                 :tender_type => tender_type,
                 :announced_after => startDate.to_s,
                 :announced_before => endDate.to_s,
                 :min_estimate => minVal.to_s,
                 :max_estimate => maxVal.to_s,
                 :min_num_bids => minBids,
                 :max_num_bids => maxBids,
                 :min_num_bidders => minBidders,
                 :max_num_bidders => maxBidders,
                 :risk_indicator => data[:risk_indicator],
                 :procurer => procurer,
                 :supplier => supplier,
                 :cpv_code => data[:cpv_code]
            }
    return queryData
  end

  def self.buildSupplierSearchParamsFromString(searchString)
    fields = searchString.split("#")
    params = {
      :supplier_search_name => self.removeWildCards(fields[0]),
      :code => self.removeWildCards(fields[1]),
      :org_type => fields[2],
      :city => self.removeWildCards(fields[3]),
      :address => self.removeWildCards(fields[4]),
      :email => self.removeWildCards(fields[5]),
      :phone_number => self.removeWildCards(fields[6]),
      :isForeign => fields[7],
      :bw_list => fields[8]
    }
    params.each do |key,param|
      if param.length == 1
        params[key] = param.gsub("_","")
      end
    end
    return params
  end

  def self.buildSupplierSearchQuery(params)
    searchParams = []
    name = params[:supplier_search_name]
    code = params[:code]
    org_type = params[:org_type]
    city = params[:city]
    address = params[:address]
    email = params[:email]
    phone_number = params[:phone_number]
    foreignOnly = params[:isForeign]
    bw_list = params[:bw_list]

    searchParams.push(name)
    searchParams.push(code)
    searchParams.push(org_type)
    searchParams.push(city)
    searchParams.push(address)
    searchParams.push(email)
    searchParams.push(phone_number)
    searchParams.push(foreignOnly)
    searchParams.push(bw_list)
    
    willSearchName = name.length > 0
    name = "%"+name+"%"
    code = "%"+code+"%"
    city = "%"+city+"%"
    address = "%"+address+"%"
    email = "%"+email+"%"
    phone_number = "%"+phone_number+"%"
    
    query = ""
    paramsList = []
    query = QueryHelper.addParamToQuery(query, true, "is_bidder", "=",paramsList)
    query = QueryHelper.addParamToQuery(query, code, "code", "LIKE",paramsList)
    query = QueryHelper.addParamToQuery(query, org_type, "org_type", "=",paramsList)
    query = QueryHelper.addParamToQuery(query, city, "city", "LIKE",paramsList)
    query = QueryHelper.addParamToQuery(query, email, "email", "LIKE",paramsList)
    query = QueryHelper.addParamToQuery(query, phone_number, "phone_number", "LIKE",paramsList)
    query = QueryHelper.addParamToQuery(query, bw_list, "bw_list_flag", "=",paramsList)
    query = QueryHelper.addParamToQuery(query, org_type, "org_type", "=",paramsList)

    if foreignOnly == '1'
      query = QueryHelper.addParamToQuery(query, 'საქართველო', "country", "NOT LIKE",paramsList)
    end
    if willSearchName
      query += " AND ( name LIKE ? OR translation LIKE ? )"
      paramsList.push(name)
      paramsList.push(name)
    end
    builtQuery = Organization.where( query, *paramsList )
    return builtQuery, searchParams
  end
  
  def self.buildProcurerSearchParamsFromString(searchString)
    fields = searchString.split("#")
    params = {
     :procurer_search_name => self.removeWildCards(fields[0]),
     :code => self.removeWildCards(fields[1]),
     :org_type => fields[2]
    }
    params.each do |key,param|
      if param.length == 1
        params[key] = param.gsub("_","")
      end
    end
    return params
  end

  def self.buildProcurerSearchQuery(params)
    searchParams = []
    name = params[:procurer_search_name]
    code = params[:code]
    org_type = params[:org_type]

    searchParams.push(name)
    searchParams.push(code)
    searchParams.push(org_type)

    queryParams = []

    willSearchName = name.length > 0

    name = "%"+name+"%"
    code = "%"+code+"%"
    #dirty hack remove this scrape side
    if org_type == "50% მეტი სახ წილ საწარმო"
      org_type = "50% მეტი სახ. წილ. საწარმო"
    end

    conditions = "is_procurer = true AND code LIKE ?"
    queryParams.push(code)
    
    if not org_type == ""
      conditions += " AND org_type = ?"
      queryParams.push(org_type)
    end
    
    if willSearchName
      conditions += " AND ( name LIKE ? OR translation LIKE ? )"
      queryParams.push("%"+name+"%")
      queryParams.push("%"+name+"%")
    end

    query = Organization.where(conditions,*queryParams)    
    return query, searchParams
  end
  
  def self.removeWildCards(string)
    return string.gsub("%","")
  end

  def self.buildTenderSearchParamsFromString(searchString)
    fields = searchString.split("#")
    params = {
      :keywords => fields[0],
      :cpvGroup => fields[1],
      :tender_registration_number => self.removeWildCards(fields[2]),
      :tender_status => fields[3],
      :tender_type => fields[4],
      :announced_after => fields[5],
      :announced_before => fields[6],
      :min_estimate => fields[7],
      :max_estimate => fields[8],
      :min_num_bids => fields[9],
      :max_num_bids => fields[10],
      :min_num_bidders => fields[11],
      :max_num_bidders => fields[12],
      :risk_indicator => fields[13],
      :procurer_name => self.removeWildCards(fields[14]),
      :supplier_name => self.removeWildCards(fields[15]),
      :cpv_code => fields[16]
    }
    params.each do |key,param|
      if param.length == 1
        params[key] = param.gsub("_","")
      end
    end
    return params
  end

  def self.addParamToQuery(query, param, sql_field, operator, paramsList)
    if param and param != "" and param != "%%"
      if query.length > 0
        query+= " AND "
      end
      query+= sql_field+" "+operator+" ?"
      paramsList.push(param)
    end
    return query
  end
  

 def self.buildTenderSearchQuery(params)
    #all params should already be in string format
    paramsList = []
    query = ""
    query = self.addParamToQuery(query, params[:tender_registration_number], "tender_registration_number", "LIKE", paramsList)
    query = self.addParamToQuery(query, params[:tender_status], "tender_status", "=", paramsList)
    query = self.addParamToQuery(query, params[:tender_type], "tender_type", "=", paramsList)
    query = self.addParamToQuery(query, params[:announced_after], "tender_announcement_date", ">=" , paramsList)
    query = self.addParamToQuery(query, params[:announced_before], "tender_announcement_date", "<=", paramsList)
    query = self.addParamToQuery(query, params[:min_estimate], "estimated_value", ">=", paramsList)
    query = self.addParamToQuery(query, params[:max_estimate], "estimated_value", "<=", paramsList)
    query = self.addParamToQuery(query, params[:min_num_bids], "num_bids", ">=", paramsList)
    query = self.addParamToQuery(query, params[:max_num_bids], "num_bids", "<=", paramsList)
    query = self.addParamToQuery(query, params[:min_num_bidders], "num_bidders", ">=", paramsList)
    query = self.addParamToQuery(query, params[:max_num_bidders], "num_bidders", "<=", paramsList)
    query = self.addParamToQuery(query, params[:risk_indicator], "risk_indicators", "LIKE", paramsList)
    query = self.addParamToQuery(query, params[:procurer], "procurer_name", "LIKE", paramsList)
    query = self.addParamToQuery(query, params[:supplier], "supplier_name", "LIKE", paramsList)
    query = self.addParamToQuery(query, params[:cpv_code], "cpv_code", "=", paramsList)


    #add cpv codes
    cpvGroup = CpvGroup.where(:id => params[:cpvGroupID]).first
    if not cpvGroup or cpvGroup.id == 1
    else      
      cpvCategories = cpvGroup.tender_cpv_classifiers
      count = 1
      queryAddition = query.length > 0
      cpvCategories.each do |category|
        conjunction = ""
        if queryAddition
          conjunction = " AND ("
        end
        if count > 1
          conjunction = " OR"
        end
        cpvDropped = self.dropZeros(category.cpv_code)
        query = query + conjunction+" cpv_code LIKE ?"
        paramsList.push(cpvDropped+"%")
        count = count + 1
      end
      if count > 1 and queryAddition
        query = query + " )"
      end
    end

    #add keywords
    if params[:keywords]
      keywords = params[:keywords].split
      count = 0
      queryAddition = query.length > 0
      conjunction = (queryAddition)? " AND (":""
      keywords.each do |word|
        if count > 0 
          conjunction = " OR"
        end
        subString = "'%"+word+"%'" 
        query+= conjunction+" addition_info LIKE ? OR supplier_name LIKE ? OR procurer_name LIKE ?"
        paramsList.push(subString)
        paramsList.push(subString)
        paramsList.push(subString)
        count+=1
      end
      query+= (queryAddition and count > 0 )? ")":""
    end
    builtQuery = Tender.where( query, *paramsList )
    return builtQuery
  end
end
