// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import "../src/RFQTrade.sol";
import "../src/RFQQuotes.sol";
import "../src/RFQLiquidations.sol";
import "../src/RFQClosePositions.sol";
import "../src/BaseFunctionality.sol";


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

contract RFQTradeTest is Test,BaseFunctionality {

    RFQTrade public rfq;
    RFQQuotes public rfqquotes;
    RFQLiquidations public rfqliquidations;
    RFQPnl public rfqPnl;
    MockUSDC public mockUSDC;
    RFQClosePositions public rfqclosepositions;
    address public rfqDAO;
    address public testoracleAddress;

    function setUp() public {
        // Deploy mock mockUSDC
        mockUSDC = new MockUSDC();
        rfq = new RFQTrade();
        rfqquotes = new RFQQuotes();
        rfqliquidations = new RFQLiquidations();
        rfqPnl = new RFQPnl();
        rfqclosepositions = new RFQClosePositions();
        rfq.initialize(oracleAddress, address(mockUSDC));
        rfq.setDefaultVariables(20 * 1e18, 100, 20, 5 * 60, 6); //setting values
        rfq.updateAffiliation(3 * 1e17, 3 * 1e17, 2 * 1e17, 2 * 1e17);//updating affiliation
        //rfq.setQuotesContract(address(rfqquotes));
        //rfq.setLiquidationsContract(address(rfqliquidations));
        //rfqquotes.initialize(address(rfq), address(rfqPnl));
        //rfqliquidations.initialize(address(rfq), address(rfqPnl));
        //rfqclosepositions.initialize(address(rfq), address(rfqPnl));
    }

    function test_deploy() public {
        assertTrue(address(rfq) != address(0), "Contract not deployed");
        console2.log("rfq Contract Address:", address(rfq));
        //assertTrue(address(rfqPnl) != address(0), "Contract not deployed");
        //console2.log("rfqPnl Contract Address:", address(rfqPnl));
        uint256 _MINIMUM_NOTIONAL = 20 * 1e18;
        uint256 _FEE_AMOUNT_BASIS_POINTS = 100;
        uint256 _MAX_OPEN_POSITIONS = 20;
        uint256 _GRACE_PERIOD = 5 * 60;
        uint256 _CANCEL_TIME_BUFFER = 6;
        //NOTE need to do these with getter functions
        /*
        assertEq(rfq.MINIMUM_NOTIONAL(), _MINIMUM_NOTIONAL); 
        assertEq(rfq.FEE_AMOUNT_BASIS_POINTS(), _FEE_AMOUNT_BASIS_POINTS);
        assertEq(rfq.MAX_OPEN_POSITIONS(), _MAX_OPEN_POSITIONS);
        //assertEq(rfq.GRACE_PERIOD(), _GRACE_PERIOD);
        assertEq(rfq.CANCEL_TIME_BUFFER(), _CANCEL_TIME_BUFFER);
        */
    }

    function testDeposit() public {
        uint256 depositAmount = 1000 * 10 ** 18; // Assuming 18 decimals
        address partyA = address(0x1);

        //console.log("Balance of partyA before mint: %s", mockUSDC.balanceOf(partyA));
        mockUSDC.mint(partyA, depositAmount);
        //console.log("Balance of partyA after mint: %s", mockUSDC.balanceOf(partyA));

        vm.startPrank(partyA);
        // Approve the rfq contract to transfer the mockUSDCs on behalf of partyA
        mockUSDC.approve(address(rfq), depositAmount);
        rfq.deposit(depositAmount);

        assertEq(rfq.getBalance(partyA), depositAmount, "Balance mismatch in rfq for partyA");
        assertEq(mockUSDC.balanceOf(partyA), 0, "mockUSDC balance mismatch in partyA");
        assertEq(mockUSDC.balanceOf(address(rfq)), depositAmount, "mockUSDC balance mismatch in rfq");
        console.log("rfq partyA deposit successful. Deposited:", rfq.getBalance(partyA) / 1e18);
        vm.stopPrank();
    }
}