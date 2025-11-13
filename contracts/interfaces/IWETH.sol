/// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IWETH {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function balanceOf(address owner) external view returns (uint);

    function allowance(address owner, address spender) external view returns (uint);

    function totalSupply() external view returns (uint);

    function approve(address spender, uint wad) external returns (bool);

    function transfer(address to, uint wad) external returns (bool);

    function transferFrom(address from, address to, uint wad) external returns (bool);

    function deposit() external payable;

    function withdraw(uint wad) external;

    event Approval(address indexed owner, address indexed spender, uint wad);
    event Transfer(address indexed from, address indexed to, uint wad);
    event Deposit(address indexed to, uint wad);
    event Withdrawal(address indexed from, uint wad);
}
