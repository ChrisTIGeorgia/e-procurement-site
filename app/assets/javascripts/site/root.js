$(function() {
  initDatePickers();
});

initDatePickers = function ()
{
  $('.dp2').datepicker();
}


$(document).ready(function() {
    $('.dataTable').dataTable( {
        "sDom": '<"top"flp><"bottom"irt><"clear">',
        "sPaginationType": "full_numbers"
    } );
} );
