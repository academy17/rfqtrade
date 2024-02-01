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

contract RFQTradeTestPnl is Test {

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

        function testCalculatePnlSameBlock() public {
            uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);

        vm.startPrank(partyB);
        //Depositing 1000 tokens
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        //PartyA deposits 1000 mockUSDCs to rfq contract
        rfq.deposit(depositAmount);
        // - setting up bOracles
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); // Dummy value for pythAddress

        uint256 initialMarginA = 1e17; //10%
        uint256 initialMarginB = 1e17; //10%
        uint256 defaultFundA = 5e16; //5%
        uint256 defaultFundB = 5e16; //5%
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
        // 2. Choose appropriate test values based on the require statements in the function:
        bool isLong = true; //party A
        uint256 bOracleId = 0; // Oracle at index 0 we just deployed.
        uint256 price = 100e18; // Price is $100
        uint256 qty = 1; 
        uint256 interestRate = 2e17; // 20%
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); // dummy value
        address frontEndAffiliateAffiliate = address(0x456); // dummy value
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18); //tokens
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        // 3. Call the function under test:
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

        //ACCEPTING QUOTE

        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
        //Accept for quote we just created
            uint256 bContractId = 0;
        //Accept Price should be a little less
            uint256 acceptPrice = 100e18; //100 dollars
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();

        vm.startPrank(partyA);
        bContract memory pnlContract = rfq.getBContractMemory(0);
        bOracle memory pnlOracle = rfq.getBOracle(0);
        (uint256 uPnLATest, bool isNegative, uint256 funding) = rfqPnl.calculateuPnlPartyA(pnlContract, pnlOracle, 150e18, pnlContract.qty); //dummy price
        console.log("PnL: ", uPnLATest / 1e18);
        console.log("IsNegative: ", isNegative);

    }

    function testCalculatePnlAInterestRate() public {
        uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);

        vm.startPrank(partyB);
        //Depositing 1000 tokens
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        //PartyA deposits 1000 mockUSDCs to rfq contract
        rfq.deposit(depositAmount);
        // - setting up bOracles
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); // Dummy value for pythAddress

        uint256 initialMarginA = 1e17; //10%
        uint256 initialMarginB = 1e17; //10%
        uint256 defaultFundA = 5e16; //5%
        uint256 defaultFundB = 5e16; //5%
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
        // 2. Choose appropriate test values based on the require statements in the function:
        bool isLong = true; //party A
        uint256 bOracleId = 0; // Oracle at index 0 we just deployed.
        uint256 price = 100e18; // Price is $100
        uint256 qty = 1; 
        uint256 interestRate = 2e17; // 20%
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); // dummy value
        address frontEndAffiliateAffiliate = address(0x456); // dummy value
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18); //tokens
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        // 3. Call the function under test:
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

        //ACCEPTING QUOTE

        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
        //Accept for quote we just created
            uint256 bContractId = 0;
        //Accept Price should be a little less
            uint256 acceptPrice = 100e18; //100 dollars
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 newTime = 365 days; //one year of funding
        vm.warp(block.timestamp + newTime);

        vm.startPrank(partyA);
        bContract memory pnlContract = rfq.getBContractMemory(0);
        bOracle memory pnlOracle = rfq.getBOracle(0);
        (uint256 uPnLATest, bool isNegative, uint256 funding) = rfqPnl.calculateuPnlPartyA(pnlContract, pnlOracle, 150e18, pnlContract.qty);
        console.log("PnL: ", uPnLATest / 1e18);
        console.log("IsNegative: ", isNegative);

    }

    function testCalculatePnlAInterestRateNegative() public {
        uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);

        vm.startPrank(partyB);
        //Depositing 1000 tokens
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        //PartyA deposits 1000 mockUSDCs to rfq contract
        rfq.deposit(depositAmount);
        // - setting up bOracles
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); // Dummy value for pythAddress

        uint256 initialMarginA = 1e17; //10%
        uint256 initialMarginB = 1e17; //10%
        uint256 defaultFundA = 5e16; //5%
        uint256 defaultFundB = 5e16; //5%
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
        // 2. Choose appropriate test values based on the require statements in the function:
        bool isLong = true; //party A
        uint256 bOracleId = 0; // Oracle at index 0 we just deployed.
        uint256 price = 100e18; // Price is $100
        uint256 qty = 1; 
        uint256 interestRate = 2e17; // 20%
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); // dummy value
        address frontEndAffiliateAffiliate = address(0x456); // dummy value
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18); //tokens
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        // 3. Call the function under test:
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

        //ACCEPTING QUOTE

        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
        //Accept for quote we just created
            uint256 bContractId = 0;
        //Accept Price should be a little less
            uint256 acceptPrice = 100e18; //100 dollars
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 newTime = 1095 days; //3 years of funding
        vm.warp(block.timestamp + newTime);

        vm.startPrank(partyA);
        bContract memory pnlContract = rfq.getBContractMemory(0);
        bOracle memory pnlOracle = rfq.getBOracle(0);
        (uint256 uPnLATest, bool isNegative, uint256 funding) = rfqPnl.calculateuPnlPartyA(pnlContract, pnlOracle, 150e18, pnlContract.qty);
        console.log("PnL: ", uPnLATest / 1e18);
        console.log("IsNegative: ", isNegative);

    }

    function testCalculatePnlANegativePnL() public {
        uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);

        vm.startPrank(partyB);
        //Depositing 1000 tokens
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        //PartyA deposits 1000 mockUSDCs to rfq contract
        rfq.deposit(depositAmount);
        // - setting up bOracles
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); // Dummy value for pythAddress

        uint256 initialMarginA = 1e17; //10%
        uint256 initialMarginB = 1e17; //10%
        uint256 defaultFundA = 5e16; //5%
        uint256 defaultFundB = 5e16; //5%
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
        // 2. Choose appropriate test values based on the require statements in the function:
        bool isLong = true; //party A
        uint256 bOracleId = 0; // Oracle at index 0 we just deployed.
        uint256 price = 100e18; // Price is $100
        uint256 qty = 1; 
        uint256 interestRate = 2e17; // 20%
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); // dummy value
        address frontEndAffiliateAffiliate = address(0x456); // dummy value
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18); //tokens
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        // 3. Call the function under test:
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

        //ACCEPTING QUOTE

        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
        //Accept for quote we just created
            uint256 bContractId = 0;
        //Accept Price should be a little less
            uint256 acceptPrice = 100e18; //100 dollars
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        //uint256 newTime = 1095 days; //3 years of funding
        //vm.warp(block.timestamp + newTime);

        vm.startPrank(partyA);
        bContract memory pnlContract = rfq.getBContractMemory(0);
        bOracle memory pnlOracle = rfq.getBOracle(0);
        (uint256 uPnLATest, bool isNegative, uint256 funding) = rfqPnl.calculateuPnlPartyA(pnlContract, pnlOracle, 50e18, pnlContract.qty);
        console.log("PnL: ", uPnLATest / 1e18);
        console.log("IsNegative: ", isNegative);
    }

    function testCalculatePnlANegativeInterestRatePositiveFlip() public {
        uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);

        vm.startPrank(partyB);
        //Depositing 1000 tokens
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        //PartyA deposits 1000 mockUSDCs to rfq contract
        rfq.deposit(depositAmount);
        // - setting up bOracles
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); // Dummy value for pythAddress

        uint256 initialMarginA = 1e17; //10%
        uint256 initialMarginB = 1e17; //10%
        uint256 defaultFundA = 5e16; //5%
        uint256 defaultFundB = 5e16; //5%
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
        // 2. Choose appropriate test values based on the require statements in the function:
        bool isLong = true; //party A
        uint256 bOracleId = 0; // Oracle at index 0 we just deployed.
        uint256 price = 100e18; // Price is $100
        uint256 qty = 1; 
        uint256 interestRate = 2e17; // 20%
        bool isAPayingAPR = false;
        address frontEndAffiliate = address(0x123); // dummy value
        address frontEndAffiliateAffiliate = address(0x456); // dummy value
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18); //tokens
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        // 3. Call the function under test:
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

        //ACCEPTING QUOTE

        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
        //Accept for quote we just created
            uint256 bContractId = 0;
        //Accept Price should be a little less
            uint256 acceptPrice = 100e18; //100 dollars
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 newTime = 1095 days; //3 years of funding
        vm.warp(block.timestamp + newTime);

        vm.startPrank(partyA);
        bContract memory pnlContract = rfq.getBContractMemory(0);
        bOracle memory pnlOracle = rfq.getBOracle(0);
        (uint256 uPnLATest, bool isNegative, uint256 funding) = rfqPnl.calculateuPnlPartyA(pnlContract, pnlOracle, 50e18, pnlContract.qty);
        console.log("PnL: ", uPnLATest / 1e18);
        console.log("IsNegative: ", isNegative);

    }

    function testCalculatePnlANegativeInterestRateAPayingAPR() public {
        uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);

        vm.startPrank(partyB);
        //Depositing 1000 tokens
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        //PartyA deposits 1000 mockUSDCs to rfq contract
        rfq.deposit(depositAmount);
        // - setting up bOracles
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); // Dummy value for pythAddress

        uint256 initialMarginA = 1e17; //10%
        uint256 initialMarginB = 1e17; //10%
        uint256 defaultFundA = 5e16; //5%
        uint256 defaultFundB = 5e16; //5%
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
        // 2. Choose appropriate test values based on the require statements in the function:
        bool isLong = true; //party A
        uint256 bOracleId = 0; // Oracle at index 0 we just deployed.
        uint256 price = 100e18; // Price is $100
        uint256 qty = 1; 
        uint256 interestRate = 2e17; // 20%
        bool isAPayingAPR = false;
        address frontEndAffiliate = address(0x123); // dummy value
        address frontEndAffiliateAffiliate = address(0x456); // dummy value
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18); //tokens
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        // 3. Call the function under test:
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

        //ACCEPTING QUOTE

        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
        //Accept for quote we just created
            uint256 bContractId = 0;
        //Accept Price should be a little less
            uint256 acceptPrice = 100e18; //100 dollars
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 newTime = 365 days; //1 year of funding
        vm.warp(block.timestamp + newTime);

        vm.startPrank(partyA);
        bContract memory pnlContract = rfq.getBContractMemory(0);
        bOracle memory pnlOracle = rfq.getBOracle(0);
        (uint256 uPnLATest, bool isNegative, uint256 funding) = rfqPnl.calculateuPnlPartyA(pnlContract, pnlOracle, 50e18, pnlContract.qty);
        console.log("PnL: ", uPnLATest / 1e18);
        console.log("IsNegative: ", isNegative);

    }

    function testCalculatePnlStaticPriceFundingAPaysAPR() public {
        uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);

        vm.startPrank(partyB);
        //Depositing 1000 tokens
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        //PartyA deposits 1000 mockUSDCs to rfq contract
        rfq.deposit(depositAmount);
        // - setting up bOracles
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); // Dummy value for pythAddress

        uint256 initialMarginA = 1e17; //10%
        uint256 initialMarginB = 1e17; //10%
        uint256 defaultFundA = 5e16; //5%
        uint256 defaultFundB = 5e16; //5%
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
        // 2. Choose appropriate test values based on the require statements in the function:
        bool isLong = true; //party A
        uint256 bOracleId = 0; // Oracle at index 0 we just deployed.
        uint256 price = 100e18; // Price is $100
        uint256 qty = 1; 
        uint256 interestRate = 2e17; // 20%
        bool isAPayingAPR = true;
        address frontEndAffiliate = address(0x123); // dummy value
        address frontEndAffiliateAffiliate = address(0x456); // dummy value
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18); //tokens
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        // 3. Call the function under test:
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

        //ACCEPTING QUOTE

        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
        //Accept for quote we just created
            uint256 bContractId = 0;
        //Accept Price should be a little less
            uint256 acceptPrice = 100e18; //100 dollars
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 newTime = 365 days; //1 year of funding
        vm.warp(block.timestamp + newTime);

        vm.startPrank(partyA);
        bContract memory pnlContract = rfq.getBContractMemory(0);
        bOracle memory pnlOracle = rfq.getBOracle(0);
        (uint256 uPnLATest, bool isNegative, uint256 funding) = rfqPnl.calculateuPnlPartyA(pnlContract, pnlOracle, 100e18, pnlContract.qty);
        console.log("PnL: ", uPnLATest / 1e18);
        console.log("IsNegative: ", isNegative);

    }

    function testCalculatePnlStaticPriceFundingBPaysAPR() public {
        uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);

        vm.startPrank(partyB);
        //Depositing 1000 tokens
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        //PartyA deposits 1000 mockUSDCs to rfq contract
        rfq.deposit(depositAmount);
        // - setting up bOracles
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); // Dummy value for pythAddress

        uint256 initialMarginA = 1e17; //10%
        uint256 initialMarginB = 1e17; //10%
        uint256 defaultFundA = 5e16; //5%
        uint256 defaultFundB = 5e16; //5%
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
        // 2. Choose appropriate test values based on the require statements in the function:
        bool isLong = true; //party A
        uint256 bOracleId = 0; // Oracle at index 0 we just deployed.
        uint256 price = 100e18; // Price is $100
        uint256 qty = 1; 
        uint256 interestRate = 2e17; // 20%
        bool isAPayingAPR = false;
        address frontEndAffiliate = address(0x123); // dummy value
        address frontEndAffiliateAffiliate = address(0x456); // dummy value
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18); //tokens
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        // 3. Call the function under test:
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

        //ACCEPTING QUOTE

        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
        //Accept for quote we just created
            uint256 bContractId = 0;
        //Accept Price should be a little less
            uint256 acceptPrice = 100e18; //100 dollars
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 newTime = 365 days; //1 year of funding
        vm.warp(block.timestamp + newTime);

        vm.startPrank(partyA);
        bContract memory pnlContract = rfq.getBContractMemory(0);
        bOracle memory pnlOracle = rfq.getBOracle(0);
        (uint256 uPnLATest, bool isNegative, uint256 funding) = rfqPnl.calculateuPnlPartyA(pnlContract, pnlOracle, 100e18, pnlContract.qty);
        console.log("PnL: ", uPnLATest / 1e18);
        console.log("IsNegative: ", isNegative);

    }


    function testDynamicIm() public {
        uint256 depositAmount = 1000e18; // Minting 1000 mockUSDCs to Party A
        address partyA = address(0x1);
        address partyB = address(0x2);
        mockUSDC.mint(partyA, depositAmount);
        mockUSDC.mint(partyB, depositAmount);

        vm.startPrank(partyB);
        //Depositing 1000 tokens
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        //PartyA deposits 1000 mockUSDCs to rfq contract
        rfq.deposit(depositAmount);
        // - setting up bOracles
        address priceFeedAddress = address(0xdeadbeefdeadbeef);
        uint256 maxDelay = 5;
        bytes32 pythAddress = bytes32(0x0); // Dummy value for pythAddress

        uint256 initialMarginA = 1e17; //10%
        uint256 initialMarginB = 1e17; //10%
        uint256 defaultFundA = 5e16; //5%
        uint256 defaultFundB = 5e16; //5%
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
        // 2. Choose appropriate test values based on the require statements in the function:
        bool isLong = true; //party A
        uint256 bOracleId = 0; // Oracle at index 0 we just deployed.
        uint256 price = 100e18; // Price is $100
        uint256 qty = 1; 
        uint256 interestRate = 2e17; // 20%
        bool isAPayingAPR = false;
        address frontEndAffiliate = address(0x123); // dummy value
        address frontEndAffiliateAffiliate = address(0x456); // dummy value
        uint256 partyABalanceBefore = rfq.getBalance(partyA);
        console.log("PartyA balance before:", partyABalanceBefore / 1e18); //tokens
        console.log("Opening Quote as PartyA...");
        vm.startPrank(partyA);
        // 3. Call the function under test:
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

        //ACCEPTING QUOTE

        uint256 partyBBalanceBefore = rfq.getBalance(partyB);
        vm.startPrank(partyB);
        //Accept for quote we just created
            uint256 bContractId = 0;
        //Accept Price should be a little less
            uint256 acceptPrice = 100e18; //100 dollars
            address backEndAffiliate = address(0x555);
        console.log("Accepting Quote as PartyB...");
            rfqquotes.acceptQuote(
                bContractId,
                acceptPrice,
                backEndAffiliate
            );
        vm.stopPrank();
        uint256 scaleFactor = 1e18;
        vm.startPrank(partyA);
        uint256 updatePrice = 150e18;
        rfq.updatePriceDummy(bOracleId, updatePrice, block.timestamp);
        vm.stopPrank();
        bContract memory testContract = rfq.getBContract(bContractId);
        bOracle memory testOracle = rfq.getBOracle(bOracleId);
        (uint256 dynamicImA, uint256 dynamicImB) = rfqPnl.dynamicIm(rfq.getBContract(bContractId), rfq.getBOracle(bOracleId));
        //dynamicImA calc
        uint256 priceRatio = acceptPrice * scaleFactor / updatePrice;
        console.log("priceRatioA: ", priceRatio);
        uint256 expectedDynamicImA = priceRatio * (initialMarginA + defaultFundA) / 1e18;
        console.log("dynamicImA: ", dynamicImA);

        //dynamicImB calc
        uint256 priceRatio2 = updatePrice * 1e18 / acceptPrice;
        console.log("priceRatio2: ", priceRatio2);
        uint256 expectedDynamicImB = (initialMarginB + defaultFundB) * priceRatio2 / 1e18;
        console.log("dynamicImB: ", dynamicImB);

        assertEq(dynamicImA, expectedDynamicImA, "dynamicImA mismatch");
        assertEq(dynamicImB, expectedDynamicImB, "dynamicImB mismatch");


    }

}