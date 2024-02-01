// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import "../src/RFQTrade.sol";
import "../src/RFQQuotes.sol";
import "../src/RFQPnl.sol";
//import "../src/RFQLiquidations.sol";
//import "../src/RFQClosePositions.sol";


import {RFQTrade} from "../src/RFQTrade.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockUSDC is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    uint256 public override totalSupply;

    function mint(address to, uint256 amount) public {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "MockmockUSDC: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(balanceOf[from] >= amount, "MockmockUSDC: insufficient balance");
        require(allowance[from][msg.sender] >= amount, "MockmockUSDC: insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract RFQTradeTestQuotes is Test {

    RFQTrade public rfq;
    RFQQuotes public rfqquotes;
    RFQPnl public rfqPnl;
    //RFQLiquidations public rfqliquidations;
    //RFQClosePositions public rfqclosepositions;

    MockUSDC public mockUSDC;
    address public rfqDAO;
    address oracleAddress;

    function setUp() public {
        mockUSDC = new MockUSDC();
        rfq = new RFQTrade();
        rfqquotes = new RFQQuotes();
        //rfqliquidations = new RFQLiquidations();
        rfqPnl = new RFQPnl();
        //rfqclosepositions = new RFQClosePositions();
        rfq.initialize(oracleAddress, address(mockUSDC));
        rfq.setDefaultVariables(20 * 1e18, 100, 20, 5 * 60, 6); 
        rfq.updateAffiliation(3 * 1e17, 3 * 1e17, 2 * 1e17, 2 * 1e17);
        rfq.setQuotesContract(address(rfqquotes));
        rfqquotes.initialize(address(rfq));
        rfqPnl.initialize(address(rfq));
    }


    function testOpenQuotePartyA() public {
        address partyA = address(0x1);
        address partyB = address(0x2);
        uint256 depositAmount = 1000e18;
        setupPartiesWithDeposit(partyA, partyB, depositAmount);
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); 
        uint256 initialMarginA = 1e17; 
        uint256 initialMarginB = 1e17; 
        uint256 defaultFundA = 5e16;
        uint256 defaultFundB = 5e16; 
        uint256 expiryA = 7 days;
        uint256 expiryB = 14 days;
        uint256 timeLockA = 3 days;
        uint256 timeLockB = 6 days;
        vm.startPrank(partyA);
        deployPriceFeed(
            maxDelay,
            _Oracle.Dummy,
            pythAddress,
            initialMarginA,
            initialMarginB,
            defaultFundA,
            defaultFundB,
            expiryA,
            expiryB,
            timeLockA,
            timeLockB
        );
        bool isLong = true; 
        uint256 bOracleId = 0; 
        uint256 price = 100e18; 
        uint256 qty = 5; 
        uint256 interestRate = 1; 
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); 
        address frontEndAffiliateAffiliate = address(0x456); 
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        rfqquotes.openQuote(
            isLong, 
            bOracleId, 
            price, 
            qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate);
        console.log("Quote opened successfully with initiator partyA!");
        vm.stopPrank();
        bContract memory newContract = rfq.getBContractMemory(rfq.getBContractLength() - 1);

        assertEq(newContract.initiator, partyA, "Incorrect contract initiator");
        assertEq(newContract.partyA, partyA, "partyA should = partyA");
        assertEq(newContract.price, price, "Incorrect price");
        assertEq(newContract.qty, qty, "Incorrect price");
        assertEq(newContract.interestRate, interestRate, "Incorrect price");
        assertEq(newContract.isAPayingAPR, true, "A should be paying APR");
        assertEq(newContract.oracleId, bOracleId, "Incorrect oracleId");
        assertEq(uint(newContract.state), uint(_State.Quote), "Incorrect State");
        assertEq(newContract.frontEndAffiliate, frontEndAffiliate, "Incorrect frontEndAffiliate");
        assertEq(newContract.frontEndAffiliateAffiliate, frontEndAffiliateAffiliate, "Incorrect frontEndAffiliateAffiliate");
        uint256 partyABalanceAfter = rfq.getBalance(partyA);
        console.log("PartyA balance after:", partyABalanceAfter / 1e18);
        console.log("PartyB balance after:", rfq.getBalance(partyB) / 1e18);
        uint256 expectedBalance = partyABalanceBefore - ((initialMarginA + defaultFundA) * qty * price / 1e18); //asserting balances deducted properly
        assertEq(rfq.getBalance(partyA), expectedBalance, "Incorrect balance after openQuote");
        assertEq(rfq.getBContractLength(), 1, "Should Increment bContractLength");
        assertEq(rfq.getOpenPositionNumber(partyA), 1);

    }

    function testAcceptQuotePartyAOpened() public {
        address partyA = address(0x1);
        address partyB = address(0x2);
        uint256 depositAmount = 1000e18;
        setupPartiesWithDeposit(partyA, partyB, depositAmount);
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); 
        uint256 initialMarginA = 1e17; 
        uint256 initialMarginB = 1e17; 
        uint256 defaultFundA = 5e16;
        uint256 defaultFundB = 5e16; 
        uint256 expiryA = 7 days;
        uint256 expiryB = 14 days;
        uint256 timeLockA = 3 days;
        uint256 timeLockB = 6 days;
        vm.startPrank(partyA);
        deployPriceFeed(
            maxDelay,
            _Oracle.Dummy,
            pythAddress,
            initialMarginA,
            initialMarginB,
            defaultFundA,
            defaultFundB,
            expiryA,
            expiryB,
            timeLockA,
            timeLockB
        );
        bool isLong = true; 
        uint256 bOracleId = 0; 
        uint256 price = 100e18; 
        uint256 qty = 5; 
        uint256 interestRate = 1; 
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); 
        address frontEndAffiliateAffiliate = address(0x456); 
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        rfqquotes.openQuote(
            isLong, 
            bOracleId, 
            price, 
            qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate);
        console.log("Quote opened successfully with initiator partyA!");
        vm.stopPrank();
        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
            uint256 bContractId = 0;
            uint256 acceptPrice = 100e18; 
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 expectedBalanceB = partyBBalanceBefore - ((initialMarginB + defaultFundB) * qty * acceptPrice / 1e18);
        bContract memory testContract = rfq.getBContractMemory(rfq.getBContractLength() - 1);
        assertEq(testContract.price, acceptPrice, "Price didn't update to the acceptedPrice");
        assertEq(testContract.backEndAffiliate, backEndAffiliate, "Incorrect back end affiliate");
        assertEq(testContract.partyB, partyB, "Incorrect partyB");
        assertEq(uint(testContract.state), uint(_State.Open), "Contract state not open");
        assertEq(rfq.getBalance(partyB), expectedBalanceB, "Incorrect balance for partyB after acceptQuote");
        console.log("PartyA balance after acceptQuote:", rfq.getBalance(partyA) ); 
        console.log("PartyB balance after acceptQuote:", rfq.getBalance(partyB) ); 


    }

    function testAcceptQuotePartyAOpenedBetterPrice() public {
        address partyA = address(0x1);
        address partyB = address(0x2);
        uint256 depositAmount = 1000e18;
        setupPartiesWithDeposit(partyA, partyB, depositAmount);
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); 
        uint256 initialMarginA = 1e17; 
        uint256 initialMarginB = 1e17; 
        uint256 defaultFundA = 5e16;
        uint256 defaultFundB = 5e16; 
        uint256 expiryA = 7 days;
        uint256 expiryB = 14 days;
        uint256 timeLockA = 3 days;
        uint256 timeLockB = 6 days;
        vm.startPrank(partyA);
        deployPriceFeed(
            maxDelay,
            _Oracle.Dummy,
            pythAddress,
            initialMarginA,
            initialMarginB,
            defaultFundA,
            defaultFundB,
            expiryA,
            expiryB,
            timeLockA,
            timeLockB
        );
        bool isLong = true; 
        uint256 bOracleId = 0; 
        uint256 price = 100e18; 
        uint256 qty = 5; 
        uint256 interestRate = 1; 
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); 
        address frontEndAffiliateAffiliate = address(0x456); 
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        rfqquotes.openQuote(
            isLong, 
            bOracleId, 
            price, 
            qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate);
        console.log("Quote opened successfully with initiator partyA!");
        vm.stopPrank();
        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
            uint256 bContractId = 0;
            uint256 acceptPrice = 50e18; 
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 expectedBalanceB = partyBBalanceBefore - ((initialMarginB + defaultFundB) * qty * acceptPrice / 1e18);
        bContract memory testContract = rfq.getBContractMemory(rfq.getBContractLength() - 1);
        assertEq(testContract.price, acceptPrice, "Price didn't update to the acceptedPrice");
        assertEq(testContract.backEndAffiliate, backEndAffiliate, "Incorrect back end affiliate");
        assertEq(testContract.partyB, partyB, "Incorrect partyB");
        assertEq(uint(testContract.state), uint(_State.Open), "Contract state not open");
        assertEq(rfq.getBalance(partyB), expectedBalanceB, "Incorrect balance for partyB after acceptQuote");
        console.log("PartyA balance after acceptQuote:", rfq.getBalance(partyA) ); 
        console.log("PartyB balance after acceptQuote:", rfq.getBalance(partyB) ); 


    }


    function testAcceptQuotePartyAOpenedBetterPriceinPool() public {
        address partyA = address(0x1);
        address partyB = address(0x2);
        address partyC = address(0x3);
        //minting for partyC
        mockUSDC.mint(partyC, 1000e18);
        vm.startPrank(partyC);
        mockUSDC.approve(address(rfq), 1000e18);
        rfq.deposit(1000e18);
        vm.stopPrank();
        uint256 depositAmount = 1000e18;
        setupPartiesWithDeposit(partyA, partyB, depositAmount);
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); 
        uint256 initialMarginA = 1e17; 
        uint256 initialMarginB = 1e17; 
        uint256 defaultFundA = 5e16;
        uint256 defaultFundB = 5e16; 
        uint256 expiryA = 7 days;
        uint256 expiryB = 14 days;
        uint256 timeLockA = 3 days;
        uint256 timeLockB = 6 days;
        vm.startPrank(partyA);
        deployPriceFeed(
            maxDelay,
            _Oracle.Dummy,
            pythAddress,
            initialMarginA,
            initialMarginB,
            defaultFundA,
            defaultFundB,
            expiryA,
            expiryB,
            timeLockA,
            timeLockB
        );
        bool isLong = true; 
        uint256 bOracleId = 0; 
        uint256 price = 100e18; 
        uint256 qty = 5; 
        uint256 interestRate = 1; 
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); 
        address frontEndAffiliateAffiliate = address(0x456); 
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        rfqquotes.openQuote(
            isLong, 
            bOracleId, 
            price, 
            qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate);
        console.log("Quote opened successfully with initiator partyA!");
        vm.stopPrank();
        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
            uint256 bContractId = 0;
            uint256 acceptPrice = 100e18; 
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();

        vm.startPrank(partyC);
        console.log("Block timestamp C: " , block.timestamp);
        console.log("PartyC Balance: ", rfq.getBalance(partyC));
        uint256 bContractIdC = 0;
        uint256 acceptPriceC = 50e18; // 50 dollars, better price...
        address backEndAffiliateC = address(0x666);

        rfqquotes.acceptQuote(
            bContractIdC,
            acceptPriceC,
            backEndAffiliateC
        );

        console.log("PartyA balance after: ", rfq.getBalance(partyA));
        console.log("PartyB balance after: ", rfq.getBalance(partyB));
        console.log("PartyC balance after: ", rfq.getBalance(partyC));
        assertEq(rfq.getBalance(partyA), rfq.getBalance(partyC), "Incorrect final balance");

}
            
    function testPartialAcceptQuotePartyAOpened() public {
        address partyA = address(0x1);
        address partyB = address(0x2);
        uint256 depositAmount = 1000e18;
        setupPartiesWithDeposit(partyA, partyB, depositAmount);
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); 
        uint256 initialMarginA = 1e17; 
        uint256 initialMarginB = 1e17; 
        uint256 defaultFundA = 5e16;
        uint256 defaultFundB = 5e16; 
        uint256 expiryA = 7 days;
        uint256 expiryB = 14 days;
        uint256 timeLockA = 3 days;
        uint256 timeLockB = 6 days;
        vm.startPrank(partyA);
        deployPriceFeed(
            maxDelay,
            _Oracle.Dummy,
            pythAddress,
            initialMarginA,
            initialMarginB,
            defaultFundA,
            defaultFundB,
            expiryA,
            expiryB,
            timeLockA,
            timeLockB
        );
        bool isLong = true; 
        uint256 bOracleId = 0; 
        uint256 price = 100e18; 
        uint256 qty = 10; 
        uint256 interestRate = 1; 
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); 
        address frontEndAffiliateAffiliate = address(0x456); 
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        rfqquotes.openQuote(
            isLong, 
            bOracleId, 
            price, 
            qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate);
        console.log("Quote opened successfully with initiator partyA!");
        vm.stopPrank();
        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
            uint256 bContractId = 0;
            address backEndAffiliate = address(0x555);
            uint256 fillAmount = 5;
        bContract memory assertContract = rfq.getBContractMemory(0);
        console.log("PartialAccepting Quote as PartyB...");
            rfqquotes.partialAcceptQuote(
            bContractId, 
            fillAmount, 
            backEndAffiliate);
        vm.stopPrank();
        uint256 expectedBalanceB = partyBBalanceBefore - ((initialMarginB + defaultFundB) * fillAmount * price / 1e18); //asserting balances deducted properly
        bContract memory newContract = rfq.getBContractMemory(rfq.getBContractLength());
        bContract memory oldContract = rfq.getBContractMemory(bContractId);        
        assertEq(newContract.price, price, "Incorrect price");
        assertEq(oldContract.backEndAffiliate, backEndAffiliate, "Incorrect back end affiliate");
        assertEq(newContract.partyA, partyA, "Incorrect partyA");
        assertEq(uint(oldContract.state), uint(_State.Open), "Old Contract should be Open");
        assertEq(uint(newContract.state), uint(_State.Quote), "New Contract should be Quote");
        assertEq(rfq.getBalance(partyB), expectedBalanceB, "Incorrect balance for partyB after acceptQuote");
        assertEq(newContract.qty, oldContract.qty - fillAmount, "Quantities should match");

    }


    function testOpenCloseQuote() public {
        address partyA = address(0x1);
        address partyB = address(0x2);
        uint256 depositAmount = 1000e18;
        setupPartiesWithDeposit(partyA, partyB, depositAmount);
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); 
        uint256 initialMarginA = 1e17; 
        uint256 initialMarginB = 1e17; 
        uint256 defaultFundA = 5e16;
        uint256 defaultFundB = 5e16; 
        uint256 expiryA = 7 days;
        uint256 expiryB = 14 days;
        uint256 timeLockA = 3 days;
        uint256 timeLockB = 6 days;
        vm.startPrank(partyA);
        deployPriceFeed(
            maxDelay,
            _Oracle.Dummy,
            pythAddress,
            initialMarginA,
            initialMarginB,
            defaultFundA,
            defaultFundB,
            expiryA,
            expiryB,
            timeLockA,
            timeLockB
        );
        bool isLong = true; 
        uint256 bOracleId = 0; 
        uint256 price = 100e18; 
        uint256 qty = 5; 
        uint256 interestRate = 1; 
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); 
        address frontEndAffiliateAffiliate = address(0x456); 
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        rfqquotes.openQuote(
            isLong, 
            bOracleId, 
            price, 
            qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate);
        console.log("Quote opened successfully with initiator partyA!");
        vm.stopPrank();
        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
            uint256 bContractId = 0;
            uint256 acceptPrice = 100e18; 
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 expectedBalanceB = partyBBalanceBefore - ((initialMarginB + defaultFundB) * qty * acceptPrice / 1e18);
        bContract memory testContract = rfq.getBContractMemory(rfq.getBContractLength() - 1);
        assertEq(testContract.price, acceptPrice, "Price didn't update to the acceptedPrice");
        assertEq(testContract.backEndAffiliate, backEndAffiliate, "Incorrect back end affiliate");
        assertEq(testContract.partyB, partyB, "Incorrect partyB");
        assertEq(uint(testContract.state), uint(_State.Open), "Contract state not open");
        assertEq(rfq.getBalance(partyB), expectedBalanceB, "Incorrect balance for partyB after acceptQuote");
        console.log("PartyA balance after acceptQuote:", rfq.getBalance(partyA) ); 
        console.log("PartyB balance after acceptQuote:", rfq.getBalance(partyB) ); 

        vm.startPrank(partyA);
        uint256[] memory _bContractIds = new uint256[](1); 
        uint256[] memory _price = new uint256[](1);
        uint256[] memory _qty = new uint256[](1);
        uint256[] memory _limitOrStop = new uint256[](1);
        uint256 _expiration = block.timestamp + 1 days;

        for (uint256 i = 0; i < _bContractIds.length; i++) {
            _bContractIds[i] = i; 
            _price[i] = 100;
            _qty[i] = 1; 
            _limitOrStop[i] = 0;
        }

        rfqquotes.openCloseQuote(
            _bContractIds, 
            _price, 
            _qty, 
            _limitOrStop, 
            _expiration, 
            msg.sender);


        bCloseQuote memory _bCloseQuote = rfq.getBCloseQuote(rfq.getBCloseQuotesLength() - 1);
        bContract memory newContract = rfq.getBContractMemory(0);

        //TODO:
        //Include Getter Function for Array Assertion
        //assertEq(_bCloseQuote.bContractIds, _bContractIds, "bContractIds do not match");
        //assertEq(_bCloseQuote.price, _price, "Prices do not match");
        //assertEq(_bCloseQuote.qty, _qty, "Quantities do not match");
        //assertEq(_bCloseQuote.limitOrStop, _limitOrStop, "Limit or Stop values do not match");
        assertEq(_bCloseQuote.initiator, newContract.initiator, "Initiator does not match");
        assertEq(_bCloseQuote.expiration, _expiration, "Expiration does not match");
        // Additional checks:
        //assertEq(_bCloseQuote.cancelTime == 0, "Cancel time should be zero");
        //assertEq(_bCloseQuote.openTime == block.timestamp, "Open time should be less than or equal to the current block timestamp");
        assertEq(uint(_bCloseQuote.state), uint(_State.Quote), "State should be set to Quote");





        }




    




//HelperFunctions

    function setupPartiesWithDeposit(
    address partyA, 
    address partyB, 
    uint256 depositAmount
    ) internal {
    // Minting mockUSDCs to both parties
    mockUSDC.mint(partyA, depositAmount);
    mockUSDC.mint(partyB, depositAmount);
    // Party B deposits tokens
    vm.startPrank(partyB);
    mockUSDC.approve(address(rfq), depositAmount);
    rfq.deposit(depositAmount);
    vm.stopPrank();
    // Party A deposits tokens
    vm.startPrank(partyA);
    mockUSDC.approve(address(rfq), depositAmount);
    rfq.deposit(depositAmount);
    vm.stopPrank();
    }

    function deployPriceFeed(
        uint256 _maxDelay,
        _Oracle _oracleType,
        bytes32 _pythAddress,
        uint256 _initialMarginA,
        uint256 _initialMarginB,
        uint256 _defaultFundA,
        uint256 _defaultFundB,
        uint256 _expiryA,
        uint256 _expiryB,
        uint256 _timeLockA,
        uint256 _timeLockB
        ) public {
        rfq.deployPriceFeed(
            _maxDelay,
            _Oracle.Dummy,
            _pythAddress,
            _initialMarginA,
            _initialMarginB,
            _defaultFundA,
            _defaultFundB,
            _expiryA,
            _expiryB,
            _timeLockA,
            _timeLockB
        );

    }

    function openQuote( 
        bool isLong,
        uint256 bOracleId,
        uint256 price,
        uint256 qty,
        uint256 interestRate, 
        bool isAPayingAPR, 
        address frontEndAffiliate, 
        address frontEndAffiliateAffiliate
    ) public {
        rfqquotes.openQuote(
            isLong, 
            bOracleId, 
            price, 
            qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate
        );
    }

    function acceptQuote( 
                uint256 bContractId,
                uint256 acceptPrice,
                address backEndAffiliate    
            ) public {
        rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
    }



}