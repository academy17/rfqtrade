// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import "../src/RFQTrade.sol";
import "../src/RFQQuotes.sol";
import "../src/RFQPnl.sol";
//import "../src/RFQLiquidations.sol";
import "../src/RFQClosePositions.sol";


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
    RFQClosePositions public rfqclosepositions;

    MockUSDC public mockUSDC;
    address public rfqDAO;
    address oracleAddress;

    function setUp() public {
        mockUSDC = new MockUSDC();
        rfq = new RFQTrade();
        rfqquotes = new RFQQuotes();
        rfqPnl = new RFQPnl();
        rfqclosepositions = new RFQClosePositions();
        //rfqliquidations = new RFQLiquidations();
        rfq.initialize(oracleAddress, address(mockUSDC));
        rfq.setDefaultVariables(20 * 1e18, 100, 20, 5 * 60, 6); 
        rfq.updateAffiliation(3 * 1e17, 3 * 1e17, 2 * 1e17, 2 * 1e17);
        rfq.setQuotesContract(address(rfqquotes));
        rfq.setClosePositionsContract(address(rfqclosepositions));
        rfqquotes.initialize(address(rfq));
        rfqclosepositions.initialize(address(rfq), address(rfqPnl));
        rfqPnl.initialize(address(rfq));
    }

    function testExpirateContractPartyAOpened() public {
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

        uint256 newTime = block.timestamp + maxDelay + 2 days;
        vm.warp(newTime);
        console.log("New Time: ", block.timestamp);
        bContract memory timeContract = rfq.getBContractMemory(0);
        console.log("openTime for bContract0: ", timeContract.openTime);
        console.log("State for bContract0: ", uint(timeContract.state));
        //Price change to 150e18
        rfq.updatePriceDummy(bOracleId, 150e18, block.timestamp);

        vm.startPrank(partyA);
        uint256 bContractIdToExpirate = rfq.getBContractLength() - 1;
        bContract memory testContractBeforeExpiry = rfq.getBContractMemory(bContractIdToExpirate);
        bOracle memory bOracleMemoryBeforeExpiry = rfq.getBOracle(rfq.getBOracleLength() - 1);
        uint256 partyABalanceBeforeExpiry = rfq.getBalance(partyA);
        uint256 partyBBalanceBeforeExpiry = rfq.getBalance(partyB);

        // Attempt to expire the contract
        console.log("Latest Price: ", bOracleMemoryBeforeExpiry.lastPrice);
        console.log("bContract Qty: ", testContractBeforeExpiry.qty);
        rfqclosepositions.expirateBContract(bContractIdToExpirate);
        bContract memory testContractAfterExpiry = rfq.getBContractMemory(bContractIdToExpirate);
        uint256 partyABalanceAfterExpiry = rfq.getBalance(partyA);
        uint256 partyBBalanceAfterExpiry = rfq.getBalance(partyB);
        assertEq(uint256(testContractAfterExpiry.state), uint256(_State.Closed));
        assert(partyABalanceAfterExpiry >= partyABalanceBeforeExpiry);
        assert(partyBBalanceAfterExpiry >= partyBBalanceBeforeExpiry);

        vm.stopPrank();

        //FAILS With Revert. Check this 

    }

    function testAcceptOpenCloseQuotePartyaOpened() public {
        uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);
        vm.startPrank(partyB);
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
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
        rfq.deployPriceFeed(
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
        console.log("Price Feed successfully deployed with index:", (rfq.getBOracleLength() - 1));
        vm.stopPrank();
        bool isLong = true; 
        uint256 bOracleId = 0; 
        uint256 price = 100e18; 
        uint256 qty = 1; 
        uint256 interestRate = 2e17; 
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); 
        address frontEndAffiliateAffiliate = address(0x456); 
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18);
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        rfqquotes.openQuote(
            isLong, 
            bOracleId, 
            price, 
            qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate);
        vm.stopPrank();
        console.log("PartyA balance after openQuote:", rfq.getBalance(partyA) / 1e18);
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

        vm.startPrank(partyA);

        uint256[] memory _bContractIds = new uint256[](1); 
        uint256[] memory _price = new uint256[](1);
        uint256[] memory _qty = new uint256[](1);
        uint256[] memory _limitOrStop = new uint256[](1);
        uint256 _expiration = block.timestamp + 1 days;
        for (uint256 i = 0; i < _bContractIds.length; i++) {
            _bContractIds[i] = i; 
            _price[i] = 151e18; 
            _qty[i] = 1; 
            _limitOrStop[i] = 0; 
        }
        console.log("opening closequote");
        rfqquotes.openCloseQuote(
            _bContractIds, 
            _price, 
            _qty, 
            _limitOrStop, 
            _expiration, 
            msg.sender);

        //PARTYB ACCEPTS CLOSE QUOTE

        vm.startPrank(partyB);

        uint256 bCloseQuoteId = rfq.getBCloseQuotesLength() - 1;
        uint256 index = 0; // Assuming we're dealing with the first bContract in the bCloseQuote
        uint256 amount = 1; // Example amount, change in next test
        bCloseQuote memory initialBCloseQuote = rfq.getBCloseQuote(bCloseQuoteId);
        bContract memory initialBContract = rfq.getBContractMemory(initialBCloseQuote.bContractIds[index]);
        console.log("calling acceptclosequote");
        console.log("bCloseQuoteLength: ", rfq.getBCloseQuotesLength());
        rfqclosepositions.acceptCloseQuote(bCloseQuoteId, index, amount);
        bCloseQuote memory updatedBCloseQuote = rfq.getBCloseQuote(bCloseQuoteId);
        bContract memory updatedBContract = rfq.getBContractMemory(updatedBCloseQuote.bContractIds[index]);
        assertEq(updatedBCloseQuote.qty[index], 0, "Quantity at index should be zero after acceptance");
        vm.stopPrank();
    }

    function testCloseMarket() public{

    }


    function AcceptQuote() public {
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