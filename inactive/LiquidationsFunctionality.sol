// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;
import "./BaseFunctionality.sol";

abstract contract LiquidationsFunctionality is BaseFunctionality {

function payOwed(uint256 amount, address target) public returns(uint256) {
    uint256 returnedAmount = 0;

    if (totalOwedAmounts[target] == 0) { 
        returnedAmount = amount;
    } else if (totalOwedAmounts[target] >= amount) { 
        totalOwedAmountPaids[target] += amount;
    } else {
        returnedAmount = amount - totalOwedAmounts[target];
        totalOwedAmountPaids[target] = totalOwedAmounts[target];
    }

    totalOwedAmounts[target] -= amount;

    emit payOwedEvent(target, returnedAmount);
    return returnedAmount;
}


    function addToOwed(uint256 deficit, address target, address receiver) internal  { 
        owedAmounts[target][receiver] += deficit;
        totalOwedAmounts[target] += deficit;
        emit addToOwedEvent(target, receiver, deficit);
    }
    

    function claimOwed(address target, address receiver) public {
        uint256 owed = owedAmounts[target][receiver];
        uint256 paid = totalOwedAmountPaids[target];

    if (paid >= owed) {
        totalOwedAmounts[target] -= owed;
        totalOwedAmountPaids[target] -= owed;
    } else {
        uint256 remainingOwed = owed - paid;
        totalOwedAmounts[target] -= remainingOwed;
        totalOwedAmountPaids[target] = 0;
        owedAmounts[target][receiver] = remainingOwed;
        }

        balances[receiver] += owed;
        emit claimOwedEvent(target, receiver, owed);
        owedAmounts[target][receiver] = 0;
    }


    function setOwedAmounts(address partyA, address partyB, uint256 amountA) external  {
            owedAmounts[partyA][partyB] = amountA;
        }  


    function decreaseTotalOwedAmounts(address partyA, uint256 amount) external {
            totalOwedAmounts[partyA] -= amount;
        }  


}