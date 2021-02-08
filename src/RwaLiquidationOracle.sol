pragma solidity >=0.5.12;

import "lib/dss-interfaces/src/dss/VatAbstract.sol";
import 'ds-value/value.sol';

contract RwaLiquidationOracle {
    // --- auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "RwaLiquidationOracle/not-authorized");
        _;
    }

    // --- math ---
    function add(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }

    VatAbstract public vat;
    struct Ilk {
        bytes32 doc; // hash of borrower's agreement with MakerDAO
        address pip; // DSValue tracking nominal loan value
        uint48  tau; // pre-agreed remediation period
        uint48  toc; // timestamp when liquidation initiated
    }
    mapping (bytes32 => Ilk) public ilks;

    // Events
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Init(bytes32 indexed ilk, uint256 val, bytes32 doc, uint48 tau);
    event Tell(bytes32 indexed ilk);
    event Cure(bytes32 indexed ilk);
    event Cull(bytes32 indexed ilk);

    constructor(address vat_) public {
        vat = VatAbstract(vat_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function init(bytes32 ilk, uint256 val, bytes32 doc, uint48 tau) external auth {
        // doc, and tau can be amended, but tau cannot decrease
        require(tau >= ilks[ilk].tau);
        ilks[ilk].doc = doc;
        ilks[ilk].tau = tau;
        if (ilks[ilk].pip == address(0)) {
            DSValue pip = new DSValue();
            ilks[ilk].pip = address(pip);
            pip.poke(bytes32(val));
        }
        emit Init(ilk, val, doc, tau);
    }

    // --- valuation adjustment ---
    function bump(bytes32 ilk, uint256 val) external auth {
        DSValue pip = DSValue(ilks[ilk].pip);
        // only cull can decrease
        require(val >= uint256(pip.read()));
        DSValue(ilks[ilk].pip).poke(bytes32(val));
    }
    // --- liquidation ---
    function tell(bytes32 ilk) external auth {
        (,,,uint256 line,) = vat.ilks(ilk);
        // DC must be set to zero first
        require(line == 0);
        require(ilks[ilk].pip != address(0));
        ilks[ilk].toc = uint48(block.timestamp);
        emit Tell(ilk);
    }
    // --- remediation ---
    function cure(bytes32 ilk) external auth {
        ilks[ilk].toc = 0;
        emit Cure(ilk);
    }
    // --- write-off ---
    function cull(bytes32 ilk) external auth {
        require(add(ilks[ilk].toc, ilks[ilk].tau) >= block.timestamp);
        DSValue(ilks[ilk].pip).poke(bytes32(uint256(1)));
        emit Cull(ilk);
    }

    // --- liquidation check ---
    // to be called by off-chain parties (e.g. a trustee) to check the standing of the loan
    function good(bytes32 ilk) external view returns (bool) {
        require(ilks[ilk].pip != address(0));
        return (ilks[ilk].toc == 0 || add(ilks[ilk].toc, ilks[ilk].tau) < block.timestamp);
    }
}
