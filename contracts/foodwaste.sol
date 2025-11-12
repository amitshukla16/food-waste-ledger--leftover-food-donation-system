// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Food Waste Ledger
 * @notice Leftover Food Donation System — records donations from donors to recipients,
 * allows claiming and tracking status (Available -> Claimed -> PickedUp -> Completed -> Cancelled).
 *
 * Features:
 *  - Donor and Recipient registration (basic metadata)
 *  - Create donation offers with metadata (description, quantity, pickup window, location note)
 *  - Claim donation (recipient asserts intent to pick up)
 *  - Confirm pickup and completion by donor or recipient
 *  - Cancelation rules and simple dispute resolution hooks (events only)
 *  - Read helpers for listing and filtering
 *
 * Note: This contract focuses on ledger & workflow only — transportation, food safety, legal
 * compliance and off-chain coordination must be handled outside this contract.
 */

contract FoodWasteLedger {
    address public owner;
    uint256 public donationCounter;

    enum DonationStatus { Available, Claimed, PickedUp, Completed, Cancelled }

    struct Donor {
        address addr;
        string name;
        string contact; // optional (phone/email/address hash)
        bool exists;
    }

    struct Recipient {

        address addr;
        string  name;
        string contact;
        bool exists;
    }

    struct Donation {
        uint256 id;
        address donor;
        address recipient; // 0 if unassigned
        string title;
        string description;
        uint256 quantity; // abstract quantity (units/portions)
        uint256 unixAvailableFrom;
        uint256 unixAvailableUntil;
        string locationNote;
        DonationStatus status;
        uint256 createdAt;
        uint256 updatedAt;
    }

    // storage
    mapping(address => Donor) public donors;
    mapping(address => Recipient) public recipients;
    mapping(uint256 => Donation) public donations;

    // convenience lists (not gas-efficient for huge data sets — acceptable for small/medium usage)
    uint256[] public donationIds;
    mapping(address => uint256[]) public donationsByDonor;
    mapping(address => uint256[]) public donationsByRecipient;

    // events
    event DonorRegistered(address indexed donor, string name);
    event RecipientRegistered(address indexed recipient, string name);
    event DonationCreated(uint256 indexed donationId, address indexed donor);
    event DonationClaimed(uint256 indexed donationId, address indexed recipient);
    event DonationPickedUp(uint256 indexed donationId, address indexed by);
    event DonationCompleted(uint256 indexed donationId);
    event DonationCancelled(uint256 indexed donationId, string reason);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyDonor(uint256 donationId) {
        require(donations[donationId].donor == msg.sender, "Only donor for this donation");
        _;
    }

    modifier onlyRegisteredDonor() {
        require(donors[msg.sender].exists, "Not a registered donor");
        _;
    }

    modifier onlyRegisteredRecipient() {
        require(recipients[msg.sender].exists, "Not a registered recipient");
        _;
    }

    constructor() {
        owner = msg.sender;
        donationCounter = 0;
        emit OwnershipTransferred(address(0), owner);
    }

    // ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "new owner is zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // registration
    function registerDonor(string calldata name, string calldata contact) external {
        Donor storage d = donors[msg.sender];
        d.addr = msg.sender;
        d.name = name;
        d.contact = contact;
        d.exists = true;
        emit DonorRegistered(msg.sender, name);
    }

    function unregisterDonor() external {
        require(donors[msg.sender].exists, "donor not registered");
        delete donors[msg.sender];
        // note: we do not remove donation lists to keep historical ledger intact
    }

    function registerRecipient(string calldata name, string calldata contact) external {
        Recipient storage r = recipients[msg.sender];
        r.addr = msg.sender;
        r.name = name;
        r.contact = contact;
        r.exists = true;
        emit RecipientRegistered(msg.sender, name);
    }

    function unregisterRecipient() external {
        require(recipients[msg.sender].exists, "recipient not registered");
        delete recipients[msg.sender];
    }

    // create donation
    function createDonation(
        string calldata title,
        string calldata description,
        uint256 quantity,
        uint256 unixAvailableFrom,
        uint256 unixAvailableUntil,
        string calldata locationNote
    ) external onlyRegisteredDonor returns (uint256) {
        require(unixAvailableUntil == 0 || unixAvailableUntil > unixAvailableFrom, "invalid availability window");

        donationCounter++;
        uint256 id = donationCounter;

        donations[id] = Donation({
            id: id,
            donor: msg.sender,
            recipient: address(0),
            title: title,
            description: description,
            quantity: quantity,
            unixAvailableFrom: unixAvailableFrom,
            unixAvailableUntil: unixAvailableUntil,
            locationNote: locationNote,
            status: DonationStatus.Available,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        donationIds.push(id);
        donationsByDonor[msg.sender].push(id);

        emit DonationCreated(id, msg.sender);
        return id;
    }

    // claim donation (recipient claims an available donation)
    function claimDonation(uint256 donationId) external onlyRegisteredRecipient {
        Donation storage d = donations[donationId];
        require(d.id != 0, "donation not found");
        require(d.status == DonationStatus.Available, "not available");
        // optional: check availability window
        if (d.unixAvailableFrom != 0) {
            require(block.timestamp >= d.unixAvailableFrom, "not yet available");
        }
        if (d.unixAvailableUntil != 0) {
            require(block.timestamp <= d.unixAvailableUntil, "offer expired");
        }

        d.recipient = msg.sender;
        d.status = DonationStatus.Claimed;
        d.updatedAt = block.timestamp;

        donationsByRecipient[msg.sender].push(donationId);

        emit DonationClaimed(donationId, msg.sender);
    }

    // donor or recipient marks picked up
    function markPickedUp(uint256 donationId) external {
        Donation storage d = donations[donationId];
        require(d.id != 0, "donation not found");
        require(d.status == DonationStatus.Claimed, "must be claimed first");
        require(msg.sender == d.donor || msg.sender == d.recipient || msg.sender == owner, "not authorized");

        d.status = DonationStatus.PickedUp;
        d.updatedAt = block.timestamp;
        emit DonationPickedUp(donationId, msg.sender);
    }

    // mark completed (food delivered and accepted)
    function completeDonation(uint256 donationId) external {
        Donation storage d = donations[donationId];
        require(d.id != 0, "donation not found");
        require(
            d.status == DonationStatus.PickedUp || d.status == DonationStatus.Claimed,
            "must be picked up or claimed"
        );
        require(msg.sender == d.donor || msg.sender == d.recipient || msg.sender == owner, "not authorized");

        d.status = DonationStatus.Completed;
        d.updatedAt = block.timestamp;
        emit DonationCompleted(donationId);
    }

    // cancel donation (donor can cancel an available or claimed donation)
    function cancelDonation(uint256 donationId, string calldata reason) external {
        Donation storage d = donations[donationId];
        require(d.id != 0, "donation not found");
        require(msg.sender == d.donor || msg.sender == owner, "only donor or owner can cancel");
        require(
            d.status == DonationStatus.Available || d.status == DonationStatus.Claimed,
            "cannot cancel in current state"
        );

        d.status = DonationStatus.Cancelled;
        d.updatedAt = block.timestamp;
        emit DonationCancelled(donationId, reason);
    }

    // view helpers
    function getDonation(uint256 donationId) external view returns (Donation memory) {
        return donations[donationId];
    }

    function latestDonations(uint256 limit) external view returns (Donation[] memory) {
        uint256 total = donationIds.length;
        if (limit == 0 || limit > total) {
            limit = total;
        }

        Donation[] memory out = new Donation[](limit);
        for (uint256 i = 0; i < limit; i++) {
            uint256 id = donationIds[total - 1 - i];
            out[i] = donations[id];
        }
        return out;
    }

    function donationsForDonor(address donor) external view returns (Donation[] memory) {
        uint256[] storage list = donationsByDonor[donor];
        Donation[] memory out = new Donation[](list.length);
        for (uint256 i = 0; i < list.length; i++) {
            out[i] = donations[list[i]];
        }
        return out;
    }

    function donationsForRecipient(address recipient) external view returns (Donation[] memory) {
        uint256[] storage list = donationsByRecipient[recipient];
        Donation[] memory out = new Donation[](list.length);
        for (uint256 i = 0; i < list.length; i++) {
            out[i] = donations[list[i]];
        }
        return out;
    }

    // small admin helpers
    function adminForceComplete(uint256 donationId) external onlyOwner {
        Donation storage d = donations[donationId];
        require(d.id != 0, "donation not found");
        d.status = DonationStatus.Completed;
        d.updatedAt = block.timestamp;
        emit DonationCompleted(donationId);
    }

    function adminForceCancel(uint256 donationId, string calldata reason) external onlyOwner {
        Donation storage d = donations[donationId];
        require(d.id != 0, "donation not found");
        d.status = DonationStatus.Cancelled;
        d.updatedAt = block.timestamp;
        emit DonationCancelled(donationId, reason);
    }

    // fallback/receive — contract should not hold ETH normally, but accept and allow owner withdrawal if sent
    receive() external payable {}

    function withdrawEther(address payable to) external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "no balance");
        to.transfer(bal);
    }

    // small utilities
    function donationCount() external view returns (uint256) {
        return donationIds.length;
    }

    // NOTE: this simple implementation stores arrays of ids on-chain; for large-scale systems prefer
    // indexing off-chain (TheGraph / users' own servers) and keep on-chain data minimal.
}

