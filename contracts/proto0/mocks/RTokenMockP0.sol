// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IStRSR.sol";

interface IRToken is IERC20 {}

contract RTokenMockP0 is ERC20, IRToken {
    using SafeERC20 for IERC20;
    using SafeERC20 for IRToken;

    IStRSR public stRSR;
    IERC20 public rsr;

    constructor(
        string memory name,
        string memory symbol,
        address rsr_
    ) ERC20(name, symbol) {
        rsr = IERC20(rsr_);
    }

    function setStRSR(address stRSR_) external {
        stRSR = IStRSR(stRSR_);
    }

    function addRSR(uint256 amount) external {
        rsr.safeApprove(address(stRSR), amount);
        stRSR.addRSR(amount);
    }

    function seizeRSR(uint256 amount) external {
        stRSR.seizeRSR(amount);
    }

    function mint(address recipient, uint256 amount) external returns (bool) {
        _mint(recipient, amount);
        return true;
    }

    function burn(address sender, uint256 amount) external returns (bool) {
        _burn(sender, amount);
        return true;
    }

    // TODO: remove after we have manager tests
    function paused() external view returns (bool) {
        return false;
    }

    function fullyCapitalized() external view returns (bool) {
        return true;
    }
}