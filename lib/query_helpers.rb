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



   def self.buildSearchParamsFromString(searchString)
    fields = searchString.split("#")
    params = {
      :cpvGroup => fields[0],
      :tender_registration_number => fields[1],
      :tender_status => fields[2],
      :announced_after => fields[3],
      :announced_before => fields[4],
      :min_estimate => fields[5],
      :max_estimate => fields[6],
      :min_num_bids => fields[7],
      :max_num_bids => fields[8],
      :min_num_bidders => fields[9],
      :max_num_bidders => fields[10],
      :risk_indicator => ""
    }
    if fields[11]
      params[:risk_indicator] = fields[11]
    end
    params.each do |key,param|
      if param.length == 1
        params[key] = param.gsub("_","")
      end
    end
    return params
  end


 def self.buildTenderSearchQuery(params)

    #all params should already be in string format
    query = ""
    addAnd = false

    addParamToQuery = Proc.new{ |param, sql_field, operator|
      if param != "" and param != "%%"
        if addAnd
          query += " AND "
        else
          addAnd = true
        end
        query += sql_field +" "+operator+" "+ "'"+param+"'"
      end
    }   

    addParamToQuery.call( params[:tender_registration_number], "tender_registration_number", "LIKE" )
    addParamToQuery.call( params[:tender_status], "tender_status", "LIKE" )
    addParamToQuery.call( params[:announced_after], "tender_announcement_date", ">=" )
    addParamToQuery.call( params[:announced_before], "tender_announcement_date", "<=" )
    addParamToQuery.call( params[:min_estimate], "estimated_value", ">=" )
    addParamToQuery.call( params[:max_estimate], "estimated_value", "<=" )
    addParamToQuery.call( params[:min_num_bids], "num_bids", ">=" )
    addParamToQuery.call( params[:max_num_bids], "num_bids", "<=" )
    addParamToQuery.call( params[:min_num_bidders], "num_bidders", ">=" )
    addParamToQuery.call( params[:max_num_bidders], "num_bidders", "<=" )
    addParamToQuery.call( params[:risk_indicator], "risk_indicators", "LIKE" )

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
        query = query + conjunction+" cpv_code LIKE '"+cpvDropped+"%'"
        count = count + 1
      end
      if count > 1 and queryAddition
        query = query + " )"
      end
    end
    return query
  end

end
