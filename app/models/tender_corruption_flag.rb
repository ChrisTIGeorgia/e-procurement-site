class TenderCorruptionFlag < ActiveRecord::Base
  belongs_to :tender
  belongs_to :corruption_indicator

  attr_accessible :id,
  :tender_id,
  :corruption_indicator_id,
  :value
end
