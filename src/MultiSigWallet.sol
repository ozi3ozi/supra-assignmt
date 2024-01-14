// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import "@openzeppelin/contracts/utils/Context.sol";

/**
 * Design Choices:
 * - I opted for a dynamic threshold. The threshold is a % based on the number of owners.
 * - For security, readability and role of each function, I tried to keep them limited to ~4 lines
 * - For flexibility when deploying, only the list of addresses provided are added to the contract. 
 * msg.sender needs to be in that list to be added
 * - Because it's a multi-sig wallet. owners must be at least 2.
 *   Threshold number must also be at least 2.
 * - InternalTransaction struct is used for adding/removing owners.
 * - Transaction struct is used for all other transactions.
 * - Executing a transaction is done automatically when the threshold is met.
 * - I used mapping to quickly check if an owner approved a transaction.
 * - I added the ability to refuse a transaction. 
 *   If owners.length - refusalCount < threshold, the transaction is cancelled.
 */
contract MultiSigWallet is Context {
// Events
    event Received(address indexed sender, uint amount);
    event Submitted(address indexed owner, uint256 indexed txId);
    event Approved(address indexed owner, uint256 indexed txId);
    event Refused(address indexed owner, uint256 indexed txId);
    event Cancelled(address indexed owner, uint256 indexed txId);
    event Executed(address indexed owner, uint256 indexed txId);

    event NewOwnerAdded(address indexed newOwner, uint256 indexed txId);
    event OldOwnerRemoved(address indexed oldOwner, uint256 indexed txId);

// Structs and variables
    struct Transaction {
        uint256 txId;
        uint256 value;
        // Incremented when approved by an owner. Avoids looping through owners to check if threshold is met.
        uint256 approvalCount;
        uint256 refusalCount;
        address to;
        bytes data;
        bool executed;
        bool cancelled;
    }

    struct InternalTransaction {
        uint256 txId;
        uint256 approvalCount;
        address to;
        bool executed;
        bool cancelled;
    }

    address[] private owners;
    Transaction[] private transactions;
    InternalTransaction[] private newOwnersToAdd;
    InternalTransaction[] private oldOwnersToRemove;
    mapping (address=>bool) public isOwner;
    // mapping (txId=> map(owner => wasApproved))
    mapping (uint=>mapping (address=>bool)) public approvedTxsByOwner;
    // mapping (txId=> map(owner => wasRefused))
    mapping (uint=>mapping (address=>bool)) public refusedTxsByOwner;
    mapping (uint=>mapping (address=>bool)) public approvedNewOwnersToAdd;
    mapping (uint=>mapping (address=>bool)) public approvedOldOwnersToRemove; 

    /** The percentage of owners required to approve a transaction. 0 < thresholdPerct <= 100
     * The goal is to keep increasing the threshold number as the number of owners increases.
     * getThreshold() will return the number of owners required to approve a transaction
     */
    uint8 private thresholdPerct;

// modifiers
    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint256 txId) {
        require(txId < transactions.length, "Tx does not exist");
        _;
    }

    modifier notApproved(uint256 txId) {
        require(!approvedTxsByOwner[txId][msg.sender], "Tx already approved");
        _;
    }

    modifier notExecuted(uint256 txId) {
        require(!transactions[txId].executed, "Tx already executed");
        _;
    }

    modifier notRefused(uint256 txId) {
        require(!refusedTxsByOwner[txId][msg.sender], "Tx already refused");
        _;
    }

    modifier notCancelled(uint256 txId) {
        require(!transactions[txId].cancelled, "Tx already cancelled");
        _;
    }

    modifier ownerToAddTxExists(uint256 txId) {
        require(txId < newOwnersToAdd.length, "Tx does not exist");
        _;
    }

    modifier ownerToRemoveTxExists(uint256 txId) {
        require(txId < oldOwnersToRemove.length, "Tx does not exist");
        _;
    }

    modifier notOwner(address newOwner) {
        require(!isOwner[newOwner], "Owner already exists");
        _;
    }

    modifier ownerExists(address newOwner) {
        require(isOwner[newOwner], "not owner");
        _;
    }

// Functions
    /**
     * @dev Constructor
     * @param _owners The owners of the multi-sig wallet. Cannot be empty
     * @param _threshold The percentage of owners required to approve a transaction. i.e. 80 for 80%
     */
    constructor (address[] memory _owners, uint8 _threshold) {
        require(_owners.length > 1, "owners count is under 2");
        require(_threshold > 0, "threshold % must be > 0");

        for (uint256 i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0), "zero address in owners list");
            require(!isOwner[_owners[i]], "owner already exists");// in case the list contains a double
            owners.push(_owners[i]);
            isOwner[_owners[i]] = true;
        }

        thresholdPerct = _threshold;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @dev The number of owners required to approve a transaction. Based on thresholdPerct.
     * Min 2 owners are required whatever the thresholdPerct.
     * @return threshold The number of owners required to approve a transaction
     */
    function getThresholdNbr() public view returns(uint16 threshold) {
        threshold = uint16(owners.length * thresholdPerct / 100);
        // 1 is added to round up unless thresholdPerct is 100
        threshold = thresholdPerct == 100 ? threshold : 
            threshold < 2 ? 2 : threshold + 1;
    }

    function getOwners() public view returns(address[] memory) {
        return owners;
    }

    function getTransactions() public view returns(Transaction[] memory) {
        return transactions;
    }

    function getNewOwnersToAdd() public view returns(InternalTransaction[] memory) {
        return newOwnersToAdd;
    }
     
    function getOldOwnersToRemove() public view returns(InternalTransaction[] memory) {
        return oldOwnersToRemove;
    }

    /**
    * @dev Submits a transaction to the multi-sig wallet for approval and execution.
    * @param to The address of the recipient of the transaction
    * @param value The amount of ether to send
    * @param data The data to send
    */
    function submit(address to, uint256 value, bytes calldata data) external onlyOwner {
        transactions.push(Transaction({
            txId: transactions.length,
            value: value,
            approvalCount: 1, // Logically, the owner submitting is the first to approve
            refusalCount: 0,
            to: to,
            data: data,
            executed: false,
            cancelled: false
        }));
        emit Submitted(msg.sender, transactions.length - 1);

        approvedTxsByOwner[transactions.length - 1][msg.sender] = true;
        emit Approved(msg.sender, transactions.length - 1);
    }

    /**
    * @dev Approves a transaction in the multi-sig wallet.
    * If the threshold is met, the transaction will be executed.
    * @param txId The id of the transaction to approve
    */
    function approve(uint256 txId) external 
            onlyOwner txExists(txId) notApproved(txId) notExecuted(txId) notCancelled(txId) {
        Transaction storage transaction = transactions[txId];
        transaction.approvalCount++;
        approvedTxsByOwner[txId][msg.sender] = true;
        emit Approved(msg.sender, txId);

        if (transaction.approvalCount >= getThresholdNbr()) {
            executeTransaction(transaction);
        }
    }

    function executeTransaction(Transaction storage transaction) internal {
        (bool success, ) = payable(transaction.to).call{value: transaction.value}(
            transaction.data);
        require(success, "failed to execute transaction");
        transaction.executed = true;
        emit Executed(msg.sender, transaction.txId);
    }

    /**
    * @dev Refuses a transaction in the multi-sig wallet.
     */
    function refuse(uint256 txId) external 
            onlyOwner txExists(txId) notRefused(txId) notExecuted(txId) notCancelled(txId) {
        Transaction storage transaction = transactions[txId];
        transaction.refusalCount++;
        refusedTxsByOwner[txId][msg.sender] = true;
        emit Refused(msg.sender, txId);

        // Transaction wont get executed even if all remaining owners approve it
        if (transaction.refusalCount > owners.length - getThresholdNbr()) { 
            transaction.cancelled = true;
            emit Cancelled(msg.sender, txId);
        }
    }

    /**
     * @dev Submits a new owner to be added to the multi-sig wallet.
     */
    function submitOwnerToAdd(address newOwner) external onlyOwner notOwner(newOwner) {
        newOwnersToAdd.push(InternalTransaction({
            txId: newOwnersToAdd.length,
            approvalCount: 1,
            to: newOwner,
            executed: false,
            cancelled: false
        }));
        emit Submitted(newOwner, newOwnersToAdd.length - 1);

        approvedNewOwnersToAdd[newOwnersToAdd.length - 1][msg.sender] = true;
        emit Approved(msg.sender, newOwnersToAdd.length - 1);
    }

    /**
     * @dev Approves a new owner to be added to the multi-sig wallet.
     * if notOwner(newOwnersToAdd[txId].to), transaction hasn't been executed.
     * If the threshold is met, the new owner will be added to the multi-sig wallet.
     * @param txId The id of the transaction to approve
     */
    function approveOwnerToAdd(uint256 txId) external 
            onlyOwner ownerToAddTxExists(txId) notOwner(newOwnersToAdd[txId].to) {
        require(!approvedNewOwnersToAdd[txId][msg.sender], "owner already approved");
        InternalTransaction storage newOwnerToAdd = newOwnersToAdd[txId];
        newOwnerToAdd.approvalCount++;
        approvedNewOwnersToAdd[txId][msg.sender] = true;
        emit Approved(msg.sender, txId);

        if (newOwnerToAdd.approvalCount >= getThresholdNbr()) {
            owners.push(newOwnerToAdd.to);
            emit NewOwnerAdded(newOwnerToAdd.to, txId);
        }
    }

    /**
     * @dev Submits an old owner to be removed from the multi-sig wallet.
     */
    function submitOwnerToRemove(address ownerToRemove) external 
            onlyOwner ownerExists(ownerToRemove) {
        oldOwnersToRemove.push(InternalTransaction({
            txId: oldOwnersToRemove.length,
            approvalCount: 1,
            to: ownerToRemove,
            executed: false,
            cancelled: false
        }));
        emit Submitted(ownerToRemove, oldOwnersToRemove.length - 1);

        approvedNewOwnersToAdd[oldOwnersToRemove.length - 1][msg.sender] = true;
        emit Approved(msg.sender, oldOwnersToRemove.length - 1);
    }

    /**
     * @dev Approves an old owner to be removed from the multi-sig wallet.
     * if ownerExists(oldOwnersToRemove[txId].to), transaction hasn't been executed.
     * If the threshold is met, the old owner will be removed from the multi-sig wallet.
     * @param txId The id of the transaction to approve
     */
    function approveOwnerToRemove(uint256 txId) external 
            onlyOwner ownerToRemoveTxExists(txId) ownerExists(oldOwnersToRemove[txId].to) {
        require(!approvedOldOwnersToRemove[txId][msg.sender], "owner already approved");
        InternalTransaction storage oldOwnerToRemove = oldOwnersToRemove[txId];
        oldOwnerToRemove.approvalCount++;
        approvedNewOwnersToAdd[txId][msg.sender] = true;
        emit Approved(msg.sender, txId);

        if (oldOwnerToRemove.approvalCount >= getThresholdNbr()) {
            delete owners[oldOwnerToRemove.txId];
            emit OldOwnerRemoved(oldOwnerToRemove.to, txId);
        }
    }
}
