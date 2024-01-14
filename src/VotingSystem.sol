// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Design choices:
 * - I used the openzeppelin contracts for their reliability.
 * - For complete transparency, removing an old candidate, voter or election is not allowed.
 * - Since an election contains candidatesWithVotes list, we don't have to use candidates list to display results.
 * - For security, readability and role of each function, I tried to keep them limited to ~4 lines
 */
contract VotingSystem is Ownable {
// events
    // The owner of the contract can add/remove candidates.
    event NewCandidateAdded(address indexed newCandidate);

    // Each voter can add/remove himself.
    event NewVoterAdded(address indexed newVoter);
    event VotedFor(address indexed voter, address indexed candidate, uint256 indexed electionId);

    // The owner of the contract can add elections.
    event NewElectionCreated(string indexed name, uint32 indexed start, uint32 indexed end);
    event ElectionEnded(string indexed name, address indexed winner, uint32 indexed totalVotes);

// structs and variables
    // structs
    struct Election {
        string name;
        uint256 id;
        uint32 start;
        uint32 end;
        uint32 totalVotes;
        address[] candidatesWithVotes; // is used to determine winner. Only candidates with votes are included.
        address winner;
    }

    struct Vote {
        uint256 id;
        address voter;
        address candidate;
    }

    struct Candidate {
        uint256 id;
        address addy;
    }

    struct Voter {
        uint256 id;
        address addy;
    }

    // variables
    Candidate[] public candidates;
    Voter[] public voters;
    Election[] public elections;
    mapping(address => bool) public candidateExists;
    mapping(address => bool) public voterExists;
    // mapping(ElectionId => mapping(candidate => votesForCandidate))
    mapping(uint256 => mapping(address => uint32)) public votesCountByCandidateByElection;
    // mapping(ElectionId => mapping(voter => hasVoted))
    mapping(uint256 => mapping(address => bool)) public hasVotedInElection;

// modifiers
    modifier notCandidate(address _candidate) {
        require(!candidateExists[_candidate], "Candidate already exists");
        _;
    }

    modifier isCandidate(address _candidate) {
        require(candidateExists[_candidate], "Candidate does not exist");
        _;
    }

    modifier notVoter() {
        require(!voterExists[_msgSender()], "Voter already exists");
        _;
    }

    modifier hasNotVoted(uint256 _electionId) {
        require(!hasVotedInElection[_electionId][_msgSender()], "Voter already voted");
        _;
    }

    modifier votingOpen(uint256 _electionId) {
        require(elections[_electionId].start <= block.timestamp, "Voting has not started");
        require(elections[_electionId].end >= block.timestamp, "Voting has ended");
        _;
    }

    modifier votingEnded(uint256 _electionId) {
        require(elections[_electionId].end < block.timestamp, "Voting is still open");
        _;
    }

    modifier isElection(uint256 _electionId) {
        require(_electionId < elections.length, "Election does not exist");
        _;
    }

// functions
    // constructor
    constructor (address[] memory _candidates) 
            Ownable(_msgSender()) {
        for (uint256 i = 0; i < _candidates.length; i++) {
            addCandidate(_candidates[i]);
        }
    }

    /**
     * @dev Candidate registration
     */ 
    function addCandidate(address _candidate) public onlyOwner() notCandidate(_candidate) {
        candidateExists[_candidate] = true;
        candidates.push(Candidate({
            id: candidates.length,
            addy: _candidate
            }));

        emit NewCandidateAdded(_candidate);
    }

    /**
     * @dev Voter registration
     */ 
    function registerToVote() public notVoter() {
        voterExists[_msgSender()] = true;
        voters.push(Voter({
            id: voters.length,
            addy: _msgSender()
        }));

        emit NewVoterAdded(_msgSender());
    }

    /**
     * @dev Election creation
     */ 
    function createElection(string calldata _name, uint32 _start, uint32 _end) public 
            onlyOwner() {
        elections.push(Election({
            name: _name,
            id: elections.length,
            start: _start,
            end: _end,
            totalVotes: 0,
            candidatesWithVotes: new address[](0),
            winner: address(0)
        }));

        emit NewElectionCreated(_name, _start, _end);
    }

    /**
     * @dev Vote for candidate
     */
    function voteFor(address _candidate, uint256 _electionId) public 
            isCandidate(_candidate) isElection(_electionId) votingOpen(_electionId) hasNotVoted(_electionId) {
        addToCandidatesWithVotes(_electionId, _candidate);
        votesCountByCandidateByElection[_electionId][_candidate]++;
        hasVotedInElection[_electionId][_msgSender()] = true;

        emit VotedFor(_candidate, _msgSender(), _electionId);
    }

    /**
     * @dev Get voting results. Returns sorted formatted results
     * From candidate with most votes to the one with least votes
     * More transparent and shows candidates tied in votes
     */
    function getVotingResultsFor(uint256 _electionId) public view
            isElection(_electionId) votingEnded(_electionId) 
            returns(bytes[] memory formattedResults) {
        address[] memory sortedCandidatesByVotes = 
            getSortedCandidatesByVotes(elections[_electionId].candidatesWithVotes, _electionId);

        formattedResults = formatElectionResults(sortedCandidatesByVotes, _electionId);
    }

// Helper functions
    /**
     * @dev Adds the candidate to the list of candidates with votes in a given election if it's their first vote.
     * Useful for the getVotingResultsFor() function
     */
    function addToCandidatesWithVotes(uint256 _electionId, address _candidate) internal {
        if (votesCountByCandidateByElection[_electionId][_candidate] == 0) {
            Election storage election = elections[_electionId];
            election.candidatesWithVotes.push(_candidate);
        }
    }

    /**
     * @dev Returns sorted list of candidates by votes in a given election
     * Useful for getVotingResultsFor()
     * Just a sorting algorithm
     */
    function getSortedCandidatesByVotes(address[] memory _candidates, uint256 _electionId) 
            internal view returns(address[] memory) {
        uint256 i = 0; uint256 j;
        while (i < _candidates.length) {
            j = i + 1;
            while (j < _candidates.length) {
                if (votesCountByCandidateByElection[_electionId][_candidates[j]] > votesCountByCandidateByElection[_electionId][_candidates[i]]) {
                    address temp = _candidates[i];
                    _candidates[i] = _candidates[j];
                    _candidates[j] = temp; 
                }
                j++;
            } 
            i++;
        }
        return _candidates;
    }

    /**
     * @dev Format election results for the getVotingResultsFor() function
     * For readability. i.e. "Candidate: 0x1234 ## Vote count: 5"
     */
    function formatElectionResults(address[] memory _sortedCandidatesByVotes, uint256 _electionId) internal view
            returns(bytes[] memory formattedResults) {
        for (uint256 x = 0; x < _sortedCandidatesByVotes.length; x++) {
            formattedResults[x] = bytes.concat(
                "Candidate: ", 
                abi.encodePacked(_sortedCandidatesByVotes[x]), 
                " ## Vote count: ", 
                abi.encodePacked(votesCountByCandidateByElection[_electionId][_sortedCandidatesByVotes[x]])
            );
        }
    }
}