/// True when [availableDate] is at least 60 days after [currentDate].
/// Used by the cancel flow and the available-dates dialog.
bool isDateGapSufficient(DateTime currentDate, DateTime availableDate) {
  return availableDate.difference(currentDate).inDays >= 60;
}
