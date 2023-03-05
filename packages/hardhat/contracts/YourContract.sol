//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * A smart contract that allows changing a state variable of the contract and tracking the changes
 * It also allows the owner to withdraw the Ether in the contract
 * @author BuidlGuidl
 */
contract YourContract {
    using SafeERC20 for IERC20;
    // Events
    event ItemListed(bytes32 indexed hash, address poster, uint index, uint price, address tokenContract);
    event ItemPriceUpdated(bytes32 indexed hash, address poster, uint index, uint newPrice);
    event ItemCanceled(bytes32 indexed hash, address poster, uint index);
    event ItemBought(bytes32 indexed hash, address poster, address buyer, uint index);
    event ItemBuyCanceled(bytes32 indexed hash, address poster, address buyer, uint index);
    event ItemSent(bytes32 indexed hash, address poster, uint index);
    event ItemReceived(bytes32 indexed hash, address poster, uint index);

    // Structs
    // TODO: See if we can pack these in fewer storage slots by rearranging
    struct ItemListing {
        bytes32 itemHash; // Chopping off first two bytes since they are predictable https://ethereum.stackexchange.com/questions/17094/how-to-store-ipfs-hash-using-bytes32
        address buyer;
        bool isSent;
        bool isReceived;
        bool isCanceled;
        uint price;
        address token; // If 0x0 address then we assume ETH
    }
    
    // State Variables
    mapping(address => mapping(uint => ItemListing)) itemListings;
    mapping(address => uint) latestIndex; // TODO: Can't this be replaced by using an array? What am I missing?
    mapping(address => mapping(address => uint)) openCollateral;
    mapping(address => mapping(address => uint)) lockedCollateral;

    function checkCollateral(address checkAddress, uint amountRequired, address tokenContract) public view returns (bool hasEnough, uint amountUnder) {
        uint currentOpenCollateral = openCollateral[checkAddress][tokenContract];
        bool hasEnough = currentOpenCollateral >= amountRequired;
        uint amountUnder = hasEnough ? 0 : amountRequired - currentOpenCollateral;
        return (hasEnough, amountUnder);
    }

    function addOpenCollateral(uint amount, address tokenContract) public {
        if (token != address(0x0)) {
            IERC20 token = IERC20(tokenContract);
            // TODO: Do we need to check allowance???
            //require(token.allowance(msg.sender, address(this)) >= price, "Token allowance for this contract too low);
            token.safeTransferFrom(msg.sender, address(this), amount);
            openCollateral[msg.sender][tokenContract] += amount;
        } else {
            // Must be native asset
            require(msg.value >= amount, "Not enough collateral to cover price");
            (bool success,) = address(this).call{value: msg.value}("");
            require(success, "Failed to receive native asset");
            openCollateral[msg.sender][address(0x0)] += msg.value;
        }
    }

    function addLockedCollateral(uint amount, uint price, address tokenContract) internal {
        if (token != address(0x0)) {
            IERC20 token = IERC20(tokenContract);
            // TODO: Do we need to check allowance???
            //require(token.allowance(msg.sender, address(this)) >= price, "Token allowance for this contract too low);
            token.safeTransferFrom(msg.sender, address(this), amount);
            openCollateral[msg.sender][tokenContract] -= price - amount;
            lockedCollateral[msg.sender][tokenContract] += price;
        } else {
            // Must be native asset
            (bool success,) = address(this).call{value: msg.value}("");
            require(success, "Failed to receive native asset");
            openCollateral[msg.sender][address(0x0)] -= price - amount;
            lockedCollateral[msg.sender][address(0x0)] += price;
        }
    }

    function lockCollateral(uint amount, address tokenContract) internal {
        openCollateral[msg.sender][tokenContract] -= price;
        lockedCollateral[msg.sender][tokenContract] += price;
    }

    function unlockCollateral(uint amount, address tokenContract) internal {
        lockedCollateral[msg.sender][tokenContract] -= price;
        openCollateral[msg.sender][tokenContract] += price;
    }

    function checkAndAddLockedCollateral(uint price, address tokenContract) internal {
        // Check that collateral has been provided
        (hasEnough, amountUnder) = checkCollateral(msg.sender, price, tokenContract);
        if (tokenContract == address(0x0)){
            // Revert is msg.value is not equal to the amount owed
            require(amountUnder == msg.value, "Reverted because we received too much value");
        }

        if (hasEnough) {
            //  Lock Collateral
            lockCollateral(price, tokenContract);
        } else {
            // Add locked collateral
            addLockedCollateral(amountUnder, price, tokenContract);
        }
    }

    function listItem(bytes32 itemHash, uint price, address tokenContract) public payable {
        // Check for correct amount of collateral and add whatever is missing
        checkAndAddLockedCollateral(price, tokenContract);
        // List item
        uint index = latestIndex[msg.sender];
        ItemListing item = itemListings[msg.sender][index];
            
        item.itemHash = itemHash;
        item.price = price;
        item.token = tokenContract;
        
        emit ItemListed(itemHash, msg.sender, index, price, tokenContract);

        ++ index;
    }

    function updateListingPrice(uint itemIndex, uint newPrice) public {
        ItemListing item = itemListings[msg.sender][itemIndex];
        require(item.itemHash != '', "You have no items at that index");
        require(item.buyer == address(0x0), "Someone has initiated buying this item, you cannot update it");

        if (newPrice > item.price) {
            // Add the difference between existing price and new price
            checkAndAddLockedCollateral(newPrice - item.price, item.token);
            item.price = newPrice;
        } else if (newPrice < item.price) {
            // Unlock the difference between existing price and new price
            unlockCollateral(item.price - newPrice, item.token);
            item.price = newPrice;
        }

        emit ItemPriceUpdated(item.itemHash, msg.sender, itemIndex, newPrice);
    }

    function cancelListing(uint itemIndex) public {
        ItemListing item = itemListings[msg.sender][itemIndex];
        require(item.itemHash != '', "You have no items at that index");
        require(item.buyer == address(0x0), "Someone has initiated buying this item, you cannot cancel it");

        item.isCanceled = true;
        unlockCollateral(item.price, item.token);
        
        emit ItemCanceled(item.itemHash, msg.sender, itemIndex);
    }

    function buyItem(address seller, uint itemIndex) public payable {
        require(seller != msg.sender, "You cannot buy your own item, try canceling instead");
        ItemListing item = itemListings[seller][itemIndex];
        require(item.buyer == address(0x0) && !item.isCanceled, "Item is no longer available");
        // Check for collateral and add any remaining, adding 2x the amount since half is the payment and half is collateral
        checkAndAddLockedCollateral(item.price * 2, item.token);
        item.buyer = msg.sender;
        
        emit ItemBought(item.itemHash, seller, msg.sender, itemIndex);
    }

    function cancelBuy(address seller, uint itemIndex) public {
        require(seller != msg.sender, "Use the cancelListing method if you want to cancel your own listing");
        ItemListing item = itemListings[seller][itemIndex];
        require(item.buyer == msg.sender && !item.isSent, "Item has already been sent and can no longer be canceled");
        item.buyer = address(0x0);
        unlockCollateral(item.price * 2, item.token);
        
        emit ItemBuyCanceled(item.itemHash, seller, msg.sender, itemIndex);
    }

    function markItemSent(uint itemIndex) public {
        ItemListing item = itemListings[msg.sender][itemIndex];
        require(item.itemHash != '', "You have no items at that index");
        require(item.buyer != address(0x0), "Nobody has bought this item, you can't mark as sent");

        item.isSent = true;
        
        emit ItemSent(item.itemHash, msg.sender, itemIndex);
    }

    function markItemReceived(address seller, uint itemIndex) public {
        ItemListing item = itemListings[seller][itemIndex];
        require(item.buyer == msg.sender, "You are not the buyer");
        require(item.isReceived == false, "Item has already been marked as received");
        item.isReceived = true;
        // Remove locked collateral from seller
        lockedCollateral[seller][item.token] -= item.price;
        // Remove locked collateral from buyer (they locked 2x the item price)
        lockedCollateral[msg.sender][item.token] -= item.price * 2;
        // Add open collateral to seller (notice how we are adding 2x the price, this is where the funds are moving from buyer to seller)
        openCollateral[seller][item.token] += item.price * 2;
        // Return initial collateral to buyer
        openCollateral[msg.sender][item.token] += item.price;

        emit ItemReceived(item.itemHash, seller, itemIndex);
    }

    function withdrawFunds(uint amount, address tokenContract) public {
        require(openCollateral[msg.sender][tokenContract] >= amount, "You don't have that amount of funds available");
        if (token != address(0x0)) {
            IERC20 token = IERC20(tokenContract);
            // TODO: Do we need to check allowance???
            //require(token.allowance(msg.sender, address(this)) >= price, "Token allowance for this contract too low);
            token.safeTransferFrom(address(this), msg.sender, amount);
            openCollateral[msg.sender][tokenContract] -= amount;
        } else {
            // Must be native asset
            (bool success,) = msg.sender.call{value: amount}("");
            require(success, "Failed to send native asset");
            openCollateral[msg.sender][address(0x0)] -= amount;
        }
    }

    function checkOpenCollateral(address addr, address tokenContract) public view returns (uint) {
        return openCollateral[addr][tokenContract];
    }


    // update price function
    // Use SafeMath?
    // accept any token for payment - how could we do this? Would require the abilty for buyer and seller to use different collaterals which gets hairy but might be possible with Uniswap oracles

    // State Variables
    address public immutable owner;
    string public greeting = "Building Unstoppable Apps!!!";
    bool public premium = false;
    uint256 public totalCounter = 0;
    mapping(address => uint) public userGreetingCounter;

    // Events: a way to emit log statements from smart contract that can be listened to by external parties
    event GreetingChange(address greetingSetter, string newGreeting, bool premium, uint256 value);

    // Constructor: Called once on contract deployment
    // Check packages/hardhat/deploy/00_deploy_your_contract.ts
    constructor(address _owner) {
        owner = _owner;
    }

    // Modifier: used to define a set of rules that must be met before or after a function is executed
    // Check the withdraw() function
    modifier isOwner() {
        // msg.sender: predefined variable that represents address of the account that called the current function
        require(msg.sender == owner, "Not the Owner");
        _;
    }

    /**
     * Function that allows anyone to change the state variable "greeting" of the contract and increase the counters
     *
     * @param _newGreeting (string memory) - new greeting to save on the contract
     */
    function setGreeting(string memory _newGreeting) public payable {
        // Print data to the hardhat chain console. Remove when deploying to a live network.
        console.log("Setting new greeting '%s' from %s",  _newGreeting, msg.sender);

        // Change state variables
        greeting = _newGreeting;
        totalCounter += 1;
        userGreetingCounter[msg.sender] += 1;

        // msg.value: built-in global variable that represents the amount of ether sent with the transaction
        if (msg.value > 0) {
            premium = true;
        } else {
            premium = false;
        }

        // emit: keyword used to trigger an event
        emit GreetingChange(msg.sender, _newGreeting, msg.value > 0, 0);
    }

    /**
     * Function that allows the owner to withdraw all the Ether in the contract
     * The function can only be called by the owner of the contract as defined by the isOwner modifier
     */
    function withdraw() isOwner public {
        (bool success,) = owner.call{value: address(this).balance}("");
        require(success, "Failed to send Ether");
    }

    /**
     * Function that allows the contract to receive ETH
     */
    receive() external payable {}
}
