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

contract RFQTradeTest is Test {

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
        rfq.setDefaultVariables(20 * 1e18, 100, 20, 5 * 60, 6); //setting values
        rfq.updateAffiliation(3 * 1e17, 3 * 1e17, 2 * 1e17, 2 * 1e17);//updating affiliation
        rfq.setQuotesContract(address(rfqquotes));
        //rfq.setLiquidationsContract(address(rfqliquidations));
        rfqquotes.initialize(address(rfq));
        rfqPnl.initialize(address(rfq));
        //rfqliquidations.initialize(address(rfq), address(rfqPnl));
        //rfqclosepositions.initialize(address(rfq), address(rfqPnl));
    }

    function test_deploy() public {
        assertTrue(address(rfq) != address(0), "Contract not deployed");
        assertTrue(address(rfqPnl) != address(0), "Contract not deployed");
        console2.log("rfq Contract Address:", address(rfq));
        uint256 _MINIMUM_NOTIONAL = 20 * 1e18;
        uint256 _FEE_AMOUNT_BASIS_POINTS = 100;
        uint256 _MAX_OPEN_POSITIONS = 20;
        uint256 _GRACE_PERIOD = 5 * 60;
        uint256 _CANCEL_TIME_BUFFER = 6;
        assertEq(rfq.MIN_NOTIONAL(), _MINIMUM_NOTIONAL); 
        assertEq(rfq.FEE_AMNT_BP(), _FEE_AMOUNT_BASIS_POINTS);
        assertEq(rfq.MAX_OPEN_POSITIONS(), _MAX_OPEN_POSITIONS);
        assertEq(rfq.GRACE_PERIOD(), _GRACE_PERIOD);
        assertEq(rfq.CANCEL_TIME_BUFFER(), _CANCEL_TIME_BUFFER);

    }

    function testDeposit() public {
        uint256 depositAmount = 1000 * 10 ** 18; 
        address partyA = address(0x1);
        mockUSDC.mint(partyA, depositAmount);
        vm.startPrank(partyA);
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);
        assertEq(rfq.getBalance(partyA), depositAmount, "Balance mismatch in rfq for partyA");
        assertEq(mockUSDC.balanceOf(partyA), 0, "mockUSDC balance mismatch in partyA");
        assertEq(mockUSDC.balanceOf(address(rfq)), depositAmount, "mockUSDC balance mismatch in rfq");
        console.log("rfq partyA deposit successful. Deposited:", rfq.getBalance(partyA) / 1e18);
        vm.stopPrank();
    }

    function testDeployPriceFeed() public {
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
        bOracle memory deployedOracle = rfq.getBOracle(rfq.getBOracleLength() - 1); // fix this, not sure why test breaks here.        assertEq(deployedOracle.priceFeedAddress, priceFeedAddress, "Incorrect priceFeedAddress");
        assertEq(deployedOracle.maxDelay, maxDelay, "Incorrect maxDelay");
        assertEq(uint(deployedOracle.oracleType), uint(_Oracle.Dummy), "Incorrect oracleType");
        assertEq(deployedOracle.pythAddress, pythAddress, "Incorrect pythAddress");
        assertEq(deployedOracle.initialMarginA, initialMarginA, "Incorrect initialMarginA");
        assertEq(deployedOracle.initialMarginB, initialMarginB, "Incorrect initialMarginB");
        assertEq(deployedOracle.defaultFundA, defaultFundA, "Incorrect defaultFundA");
        assertEq(deployedOracle.defaultFundB, defaultFundB, "Incorrect defaultFundB");
        assertEq(deployedOracle.expiryA, expiryA, "Incorrect expiryA");
        assertEq(deployedOracle.expiryB, expiryB, "Incorrect expiryB");
        assertEq(deployedOracle.timeLockA, timeLockA, "Incorrect timeLockA");
        assertEq(deployedOracle.timeLockB, timeLockB, "Incorrect timeLockB");
        console.log("Oracle Price Feed Successfully Deployed!");

    }   



}