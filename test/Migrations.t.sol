pragma solidity 0.8.26;

import "../lib/forge-std/src/Test.sol";

import "./helpers/IMigrations.sol";

contract MigrationsTest is Test {
    IMigrations internal migrations;

    function setUp() public {
        migrations = IMigrations(deployCode("out/Migrations.sol/Migrations.json"));
    }

    function test_constructor() public {
        assertEq(migrations.owner(), address(this));
    }

    function test_setCompleted() public {
        migrations.setCompleted(123);
        assertEq(migrations.last_completed_migration(), 123);
    }

    function test_setCompleted_Restricted() public {
        vm.prank(makeAddr("alien"));
        migrations.setCompleted(123);
        assertEq(migrations.last_completed_migration(), 0);
    }

    function test_upgrade() public {
        vm.prank(address(migrations));
        IMigrations newMigrations = IMigrations(deployCode("out/Migrations.sol/Migrations.json"));
        migrations.setCompleted(123);
        migrations.upgrade(address(newMigrations));
        assertEq(newMigrations.last_completed_migration(), 123);
    }

    function test_upgrade_Restricted() public {
        IMigrations newMigrations = IMigrations(deployCode("out/Migrations.sol/Migrations.json"));
        migrations.setCompleted(123);
        vm.prank(makeAddr("alien"));
        migrations.upgrade(address(newMigrations));
        assertEq(newMigrations.last_completed_migration(), 0);
    }
}
