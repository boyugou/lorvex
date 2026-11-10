import Testing

@testable import LorvexCore

/// A reorder writes as few rows as it can: each rewritten list or habit syncs
/// whole and would replace what another device changed in it meanwhile.
@Suite("Reorder positions move as few rows as possible")
struct ReorderPositionsTests {
  private func changed(_ current: [Int64]) -> Int {
    zip(current, ReorderPositions.assign(current)).filter { $0 != $1 }.count
  }

  private func isStrictlyIncreasing(_ values: [Int64]) -> Bool {
    zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
  }

  @Test
  func anOrderThatAlreadyIncreasesIsLeftAlone() {
    #expect(ReorderPositions.assign([]) == [])
    #expect(ReorderPositions.assign([7]) == [7])
    #expect(ReorderPositions.assign([0, 3, 9, 4096]) == [0, 3, 9, 4096])
  }

  @Test
  func oneRowMovedBetweenSpacedNeighborsChangesOneRow() {
    // The last row dragged to second place.
    let current: [Int64] = [1024, 4096, 2048, 3072]
    let assigned = ReorderPositions.assign(current)
    #expect(assigned == [1024, 1536, 2048, 3072])

    // To the front, where it lands between zero and the first row.
    #expect(ReorderPositions.assign([3072, 1024, 2048]) == [511, 1024, 2048])
    // To the end, a step past the last row.
    #expect(ReorderPositions.assign([2048, 3072, 1024]) == [2048, 3072, 4096])
  }

  @Test
  func rowsThatNeverHadGapsAreSpacedOnce() {
    // A dense board, one row moved up between two neighbors with no room.
    let assigned = ReorderPositions.assign([0, 3, 1, 2])
    #expect(assigned == [1024, 2048, 3072, 4096])
    // From then on a move has room.
    #expect(changed([1024, 4096, 2048, 3072]) == 1)
  }

  @Test
  func rowsAllAtZeroKeepOneAndPlaceTheRestAfterIt() {
    let assigned = ReorderPositions.assign([0, 0, 0])
    #expect(assigned == [0, 1024, 2048])
  }

  @Test
  func everyResultIncreasesStrictlyAndStaysInRange() {
    let cases: [[Int64]] = [
      [3, 2, 1, 0], [5, 5, 5, 5, 5], [0, 1, 0, 1, 0], [9, 0, 8, 1, 7, 2],
      [1024, 1025, 1024, 2048], [Int64.max, 0, 5], [0, Int64.max / 2, 1],
      [2048, 1024, 1025, 1026],
    ]
    for current in cases {
      let assigned = ReorderPositions.assign(current)
      #expect(assigned.count == current.count)
      #expect(isStrictlyIncreasing(assigned), "\(current) became \(assigned)")
      #expect(assigned.allSatisfy { $0 >= 0 })
    }
  }

  @Test
  func aRowBetweenTwoThatStayLandsStrictlyBetweenThem() {
    // Two rows to place in a gap that holds exactly two.
    #expect(ReorderPositions.assign([10, 50, 60, 13, 20, 30]) == [10, 11, 12, 13, 20, 30])
  }
}
