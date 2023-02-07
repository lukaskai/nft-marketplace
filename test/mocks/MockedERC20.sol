// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockedERC20 is ERC20 {
    constructor() ERC20("Mocked", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
