// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    uint private _next;

    constructor() ERC721("Mock", "MCK") {}

    function mint(address to, uint id) external {
        _mint(to, id);
    }
}
