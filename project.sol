Skip to content
You said:
Create a Solidity project named: food  waste ledger -leftover food donation system 
Write a smart contract Project.sol with 2–3 core functions.
Create a project folder named after your project title.
Add a README.md with:
- Project Title
- Project Description
- Project Vision
- Key Features
ChatGPT said:
Here’s a complete structure and content for your Solidity project: Food Waste Ledger – Leftover Food Donation System.

📁 Folder Structure
food-waste-ledger/
│
├── contracts/
│   └── Project.sol
│
├── README.md
│
└── hardhat.config.js   (optional if using Hardhat or Truffle)
🧠 Smart Contract: Project.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Food Waste Ledger - Leftover Food Donation System
 * @dev This contract tracks leftover food donations and their recipients
 *      to promote transparency and reduce food waste.
 */
contract Project {
    address public owner;

    struct Donation {
        uint256 id;
        address donor;
        string foodDescription;
        uint256 quantity;
        string location;
        bool claimed;
        address recipient;
    }

    uint256 public donationCount;
    mapping(uint256 => Donation) public donations;

    event FoodDonated(uint256 id, address indexed donor, string description, uint256 quantity, string location);
    event FoodClaimed(uint256 id, address indexed recipient);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action.");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Add a new food donation.
     * @param _foodDescription Description of the leftover food.
     * @param _quantity Quantity of food items (in units or kg).
     * @param _location Location where the food is available.
     */
    function addDonation(
        string memory _foodDescription,
        uint256 _quantity,
        string memory _location
    ) public {
        donationCount++;
        donations[donationCount] = Donation(
            donationCount,
            msg.sender,
            _foodDescription,
            _quantity,
            _location,
            false,
            address(0)
        );

        emit FoodDonated(donationCount, msg.sender, _foodDescription, _quantity, _location);
    }

    /**
     * @dev Claim a food donation.
     * @param _donationId The ID of the donation being claimed.
     */
    function claimDonation(uint256 _donationId) public {
        Donation storage donation = donations[_donationId];
        require(!donation.claimed, "Donation already claimed.");
        require(donation.donor != msg.sender, "Donor cannot claim their own donation.");

        donation.claimed = true;
        donation.recipient = msg.sender;

        emit FoodClaimed(_donationId, msg.sender);
    }

    /**
     * @dev Retrieve details of a donation.
     * @param _donationId The ID of the donation.
     */
    function getDonation(uint256 _donationId)
        public
        view
        returns (
            uint256,
            address,
            string memory,
            uint256,
            string memory,
            bool,
            address
        )
    {
        Donation memory d = donations[_donationId];
        return (d.id, d.donor, d.foodDescription, d.quantity, d.location, d.claimed, d.recipient);
    }
}
