//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

/**
 * Enables two parties to exchange anything by collateralizing each side to safe guard against perverse incentives
 */
contract CollateralizedExchange {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    // Events
    event ItemListed(bytes32 indexed hash, address seller, uint index, uint price, address tokenContract);
    event ItemPriceUpdated(bytes32 indexed hash, address seller, uint index, uint newPrice);
    event ItemCanceled(bytes32 indexed hash, address seller, uint index);
    event ItemBought(bytes32 indexed hash, address seller, address buyer, uint index);
    event ItemBuyCanceled(bytes32 indexed hash, address seller, address buyer, uint index);
    event ItemSent(bytes32 indexed hash, address seller, uint index);
    event ItemReceived(bytes32 indexed hash, address seller, uint index);

    // Struct
    struct ItemListing {
        bytes32 itemHash; // slot0 - Chopping off first two bytes since they are predictable https://ethereum.stackexchange.com/questions/17094/how-to-store-ipfs-hash-using-bytes32
        address buyer; // slot1 - 20 bytes
        bool isSent; // slot1 - 1 byte
        bool isReceived; // slot1 - 1 byte
        bool isCanceled; // slot1 - 1 byte
        uint price; // slot2 - 32 bytes
        address token; // slot3 - 20 bytes - If 0x0 address then we assume ETH
    }
    
    // State Variables
    mapping(address => mapping(uint => ItemListing)) itemListings;
    mapping(address => uint) latestIndex;
    mapping(address => mapping(address => uint)) openCollateral;
    mapping(address => mapping(address => uint)) lockedCollateral;

    function checkCollateral(address checkAddress, uint amountRequired, address tokenContract) internal view returns (bool hasEnough, uint amountUnder) {
        uint currentOpenCollateral = openCollateral[checkAddress][tokenContract];
        hasEnough = currentOpenCollateral >= amountRequired;
        amountUnder = hasEnough ? 0 : SafeMath.sub(amountRequired, currentOpenCollateral);
        return (hasEnough, amountUnder);
    }

    function addOpenCollateral(uint amount, address tokenContract) public payable {
        if (tokenContract != address(0x0)) {
            IERC20 token = IERC20(tokenContract);
            token.safeTransferFrom(msg.sender, address(this), amount);
            openCollateral[msg.sender][tokenContract] = openCollateral[msg.sender][tokenContract].add(amount);
        } else {
            // Must be native asset
            require(msg.value >= amount, "Not enough collateral to cover price");
            (bool success,) = address(this).call{value: msg.value}("");
            require(success, "Failed to receive native asset");
            openCollateral[msg.sender][address(0x0)] = openCollateral[msg.sender][address(0x0)].add(msg.value);
        }
    }

    /* 
    ** This function handles a scenario when a user already has some openCollateral
    ** so they only need to transfer value that is equal to the difference between 
    ** item price and existing OC amount. Then this function locks the proper amount 
    ** required to be locked by the item they are purchasing or selling
    */
    function addLockedCollateral(uint amount, uint price, address tokenContract) internal {
        if (tokenContract != address(0x0)) {
            IERC20 token = IERC20(tokenContract);
            token.safeTransferFrom(msg.sender, address(this), amount);
            lockCollateral(SafeMath.sub(price, amount), price, tokenContract);
        } else {
            // Must be native asset
            (bool success,) = address(this).call{value: msg.value}("");
            require(success, "Failed to receive native asset");
            lockCollateral(SafeMath.sub(price, amount), price, address(0x0));
        }
    }

    /*
    ** This function accounts for the scenario where a user may already have some openCollateral
    ** hence different amounts may need to be added/removed from locked and open collateral.
    */
    function lockCollateral(uint openToSub, uint lockedToAdd, address tokenContract) internal {
        openCollateral[msg.sender][tokenContract] = openCollateral[msg.sender][tokenContract].sub(openToSub);
        lockedCollateral[msg.sender][tokenContract] = lockedCollateral[msg.sender][tokenContract].add(lockedToAdd);
    }

    function unlockCollateral(uint amount, address tokenContract) internal {
        lockedCollateral[msg.sender][tokenContract] = lockedCollateral[msg.sender][tokenContract].sub(amount);
        openCollateral[msg.sender][tokenContract] = openCollateral[msg.sender][tokenContract].add(amount);
    }

    function checkAndAddLockedCollateral(uint price, address tokenContract) internal {
        // Check that collateral has been provided
        (bool hasEnough, uint amountUnder) = checkCollateral(msg.sender, price, tokenContract);
        if (tokenContract == address(0x0)) {
            // Revert if msg.value is not equal to the amount owed
            require(amountUnder == msg.value, "Reverted because we received too much value");
        }

        if (hasEnough) {
            // Lock Collateral
            lockCollateral(price, price, tokenContract);
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
        ItemListing storage item = itemListings[msg.sender][index];
            
        item.itemHash = itemHash;
        item.price = price;
        item.token = tokenContract;
        
        emit ItemListed(itemHash, msg.sender, index, price, tokenContract);

        latestIndex[msg.sender]++;
    }

    function updateListingPrice(uint itemIndex, uint newPrice) public payable {
        ItemListing storage item = itemListings[msg.sender][itemIndex];
        require(item.itemHash != '', "You have no items at that index");
        require(item.price != newPrice, "You must provide a new price");
        require(item.isCanceled != true, "You cannot update the price of a cancelled listing");
        require(item.buyer == address(0x0), "Someone has initiated buying this item, you cannot update it");

        if (newPrice > item.price) {
            // Add the difference between existing price and new price
            checkAndAddLockedCollateral(SafeMath.sub(newPrice, item.price), item.token);
            item.price = newPrice;
        } else if (newPrice < item.price) {
            // Unlock the difference between existing price and new price
            unlockCollateral(SafeMath.sub(item.price, newPrice), item.token);
            item.price = newPrice;
        }

        emit ItemPriceUpdated(item.itemHash, msg.sender, itemIndex, newPrice);
    }

    function cancelListing(uint itemIndex) public {
        ItemListing storage item = itemListings[msg.sender][itemIndex];
        require(item.itemHash != '', "No item at that index");
        require(item.buyer == address(0x0), "Someone has initiated buying this item, you cannot cancel it");

        item.isCanceled = true;
        unlockCollateral(item.price, item.token);
        
        emit ItemCanceled(item.itemHash, msg.sender, itemIndex);
    }

    function buyItem(address seller, uint itemIndex) public payable {
        require(seller != msg.sender, "You cannot buy your own item, try canceling instead");
        ItemListing storage item = itemListings[seller][itemIndex];
        require(item.buyer == address(0x0) && !item.isCanceled, "Item is no longer available");
        // Check for collateral and add any remaining, adding 2x the amount since half is the payment and half is collateral
        checkAndAddLockedCollateral(SafeMath.mul(item.price, 2), item.token);
        item.buyer = msg.sender;
        
        emit ItemBought(item.itemHash, seller, msg.sender, itemIndex);
    }

    function cancelBuy(address seller, uint itemIndex) public {
        require(seller != msg.sender, "Use the cancelListing method if you want to cancel your own listing");
        ItemListing storage item = itemListings[seller][itemIndex];
        require(item.buyer == msg.sender && !item.isSent, "Item has already been sent and can no longer be canceled");
        item.buyer = address(0x0);
        unlockCollateral(SafeMath.mul(item.price, 2), item.token);
        
        emit ItemBuyCanceled(item.itemHash, seller, msg.sender, itemIndex);
    }

    function markItemSent(uint itemIndex) public {
        ItemListing storage item = itemListings[msg.sender][itemIndex];
        require(item.itemHash != '', "You have no items at that index");
        require(item.buyer != address(0x0), "Nobody has bought this item, you can't mark as sent");

        item.isSent = true;
        
        emit ItemSent(item.itemHash, msg.sender, itemIndex);
    }

    function markItemReceived(address seller, uint itemIndex) public {
        ItemListing storage item = itemListings[seller][itemIndex];
        require(item.buyer == msg.sender, "You are not the buyer");
        require(item.isReceived == false, "Item has already been marked as received");
        item.isReceived = true;
        // Remove locked collateral from seller
        lockedCollateral[seller][item.token] = lockedCollateral[seller][item.token].sub(item.price);
        // Remove locked collateral from buyer (they locked 2x the item price)
        lockedCollateral[msg.sender][item.token] = lockedCollateral[msg.sender][item.token].sub(SafeMath.mul(item.price, 2));
        // Add open collateral to seller (notice how we are adding 2x the price, this is where the funds are moving from buyer to seller)
        openCollateral[seller][item.token] = openCollateral[seller][item.token].add(SafeMath.mul(item.price, 2));
        // Return initial collateral to buyer
        openCollateral[msg.sender][item.token] = openCollateral[msg.sender][item.token].add(item.price);

        emit ItemReceived(item.itemHash, seller, itemIndex);
    }

    function withdrawFunds(uint amount, address tokenContract) public {
        require(openCollateral[msg.sender][tokenContract] >= amount, "You don't have that amount of funds available");
        if (tokenContract != address(0x0)) {
            IERC20 token = IERC20(tokenContract);
            token.safeTransfer(msg.sender, amount);
            openCollateral[msg.sender][tokenContract] = openCollateral[msg.sender][tokenContract].sub(amount);
        } else {
            // Must be native asset
            (bool success,) = msg.sender.call{value: amount}("");
            require(success, "Failed to send native asset");
            openCollateral[msg.sender][address(0x0)] = openCollateral[msg.sender][address(0x0)].sub(amount);
        }
    }

    function checkOpenCollateral(address addr, address tokenContract) public view returns (uint) {
        return openCollateral[addr][tokenContract];
    }

    function getItem(address seller, uint itemIndex) public view returns (ItemListing memory) {
        return itemListings[seller][itemIndex];
    }

    function getItems(address seller) public view returns (ItemListing[] memory) {
        ItemListing[] memory items = new ItemListing[](latestIndex[seller]);
        for (uint i; i < latestIndex[seller]; i ++) {
            items[i] = itemListings[seller][i];
        }
        return items;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

}
