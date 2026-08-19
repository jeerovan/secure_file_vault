class SyncCursor {
  int timestamp;
  int rowId;

  SyncCursor({required this.timestamp, required this.rowId});

  void advance(int candidateTimestamp, int candidateRowId) {
    if (candidateTimestamp > timestamp ||
        (candidateTimestamp == timestamp && candidateRowId > rowId)) {
      timestamp = candidateTimestamp;
      rowId = candidateRowId;
    }
  }
}
