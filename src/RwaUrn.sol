pragma solidity 0.5.12;

import "lib/dss-interfaces/src/dss/VatAbstract.sol";
import "lib/dss-interfaces/src/dapp/DSTokenAbstract.sol";
import "lib/dss-interfaces/src/dss/GemJoinAbstract.sol";
import "lib/dss-interfaces/src/dss/DaiJoinAbstract.sol";

import "./lib.sol";

contract RwaUrn is LibNote {
    // --- auth ---
    mapping (address => uint) public wards;
    mapping (address => uint) public can;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "RwaUrn/not-authorized");
        _;
    }
    function hope(address usr) external auth { can[usr] = 1; }
   function nope(address usr) external auth { can[usr] = 0; }
    modifier operator {
        require(can[msg.sender] == 1, "RwaUrn/not-operator");
        _;
    }

    VatAbstract  public vat;
    DSTokenAbstract public gem;
    GemJoinAbstract public gemJoin;
    DaiJoinAbstract public daiJoin;
    address  public fbo; // routing conduit?

    // --- init ---
    constructor(address vat_, address gemJoin_, address daiJoin_, address fbo_, address gem_) public {
        vat = VatAbstract(vat_);
        // gem approve in constructor uint(-1)
        gemJoin = GemJoinAbstract(gemJoin_);
        daiJoin = DaiJoinAbstract(daiJoin_);
        fbo = fbo_;
        wards[msg.sender] = 1;
        gem = DSTokenAbstract(gem_);
    }

    // --- administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "fbo") fbo = data;
        else revert("RwaUrn/unrecognised-param");
    }

    // --- cdp operation ---
    // n.b. DAI can only go to fbo
    function lock(uint256 wad) external operator {
        DSTokenAbstract(gemJoin.gem()).transferFrom(msg.sender, address(this), wad);
        gem.approve(address(gemJoin), wad);
        gemJoin.join(address(msg.sender), wad);
        vat.frob(gemJoin.ilk(), address(this), address(this), address(this), int(wad), 0);
    }
    function free(uint256 wad) external operator {
        vat.frob(gemJoin.ilk(), address(this), address(this), address(this), -int(wad), 0);
        gemJoin.exit(address(msg.sender), wad);
        DSTokenAbstract(gemJoin.gem()).transfer(msg.sender, wad);
    }
    function draw(uint256 wad) external operator {
        vat.frob(gemJoin.ilk(), address(this), address(this), address(this), 0, int(wad));
        daiJoin.exit(fbo, wad);
    }
    function wipe(uint256 wad) external operator {
        daiJoin.join(address(this), wad);
        vat.frob(gemJoin.ilk(), address(this), address(this), address(this), 0, -int(wad));
    }
}
