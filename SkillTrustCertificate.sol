// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  SkillTrust Academy - Blockchain Digital Certificate Verification System
 * @notice ระบบออกและตรวจสอบใบรับรองดิจิทัล
 *
 *  กฎทางธุรกิจ:
 *   - ใบรับรองแต่ละใบต้องมีรหัสไม่ซ้ำกัน (certId unique)
 *   - ผู้ไม่ได้รับอนุญาตห้ามออก/เพิกถอนใบรับรอง (onlyIssuer / onlyAdmin)
 *   - ไม่เก็บข้อมูลส่วนบุคคลบน Public Blockchain โดยตรง
 *       -> เก็บเพียง recipientHash = keccak256(ชื่อ-นามสกุล | certId) และ documentHash ของไฟล์
 *   - การเพิกถอนไม่ลบข้อมูล แต่เปลี่ยนสถานะ เพื่อคงประวัติการออกไว้
 */
contract SkillTrustCertificate {
    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------
    enum Status { NotFound, Valid, Revoked }

    struct Course {
        string  courseCode;     // รหัสหลักสูตร เช่น AI-101
        string  name;           // ชื่อหลักสูตร
        string  description;    // รายละเอียดการอบรม
        uint16  durationHours;  // จำนวนชั่วโมงอบรม
        bool    active;
        bool    exists;
        uint64  createdAt;
    }

    struct Certificate {
        string  certId;         // รหัสอ้างอิงใบรับรอง (ไม่ซ้ำ)
        string  courseCode;
        address recipient;      // Wallet ของผู้เข้าอบรม (ใช้กับ Dashboard)
        bytes32 recipientHash;  // hash ของข้อมูลผู้รับ (ไม่เก็บชื่อจริงบนเชน)
        bytes32 documentHash;   // hash ของไฟล์ใบรับรอง (PDF/PNG)
        uint64  issueDate;      // วันที่ออก (unix timestamp ตามที่ระบุ)
        uint64  recordedAt;     // เวลาที่บันทึกลงบล็อกเชน
        address issuer;
        bool    revoked;
        uint64  revokedAt;
        string  revokeReason;
        bool    exists;
    }

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------
    address public owner;
    mapping(address => bool) public isIssuer;
    address[] private issuerList;

    mapping(string => Course) private courses;
    string[] private courseCodes;

    mapping(string => Certificate) private certificates;
    string[] private certIds;

    mapping(address => string[]) private recipientCerts;
    mapping(bytes32 => string) private documentHashToCertId;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event IssuerAdded(address indexed issuer);
    event IssuerRemoved(address indexed issuer);
    event CourseCreated(string courseCode, string name, uint16 durationHours);
    event CourseStatusChanged(string courseCode, bool active);
    event CertificateIssued(string certId, string courseCode, address indexed recipient, bytes32 documentHash, address indexed issuer);
    event CertificateRevoked(string certId, string reason, address indexed revokedBy);

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Only admin");
        _;
    }

    modifier onlyIssuer() {
        require(msg.sender == owner || isIssuer[msg.sender], "Not authorized issuer");
        _;
    }

    constructor() {
        owner = msg.sender;
        isIssuer[msg.sender] = true;
        issuerList.push(msg.sender);
        emit OwnershipTransferred(address(0), msg.sender);
        emit IssuerAdded(msg.sender);
    }

    // ------------------------------------------------------------------
    // Admin / Role management
    // ------------------------------------------------------------------
    function addIssuer(address account) external onlyOwner {
        require(account != address(0), "Invalid address");
        require(!isIssuer[account], "Already issuer");
        isIssuer[account] = true;
        issuerList.push(account);
        emit IssuerAdded(account);
    }

    function removeIssuer(address account) external onlyOwner {
        require(isIssuer[account], "Not an issuer");
        require(account != owner, "Cannot remove admin");
        isIssuer[account] = false;
        for (uint256 i = 0; i < issuerList.length; i++) {
            if (issuerList[i] == account) {
                issuerList[i] = issuerList[issuerList.length - 1];
                issuerList.pop();
                break;
            }
        }
        emit IssuerRemoved(account);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        if (!isIssuer[newOwner]) {
            isIssuer[newOwner] = true;
            issuerList.push(newOwner);
            emit IssuerAdded(newOwner);
        }
    }

    function getIssuers() external view returns (address[] memory) {
        return issuerList;
    }

    // ------------------------------------------------------------------
    // 1) Create Training Course
    // ------------------------------------------------------------------
    function createCourse(
        string calldata courseCode,
        string calldata name,
        string calldata description,
        uint16 durationHours
    ) external onlyOwner {
        require(bytes(courseCode).length > 0, "Course code required");
        require(bytes(name).length > 0, "Course name required");
        require(!courses[courseCode].exists, "Course code already exists");

        courses[courseCode] = Course({
            courseCode: courseCode,
            name: name,
            description: description,
            durationHours: durationHours,
            active: true,
            exists: true,
            createdAt: uint64(block.timestamp)
        });
        courseCodes.push(courseCode);
        emit CourseCreated(courseCode, name, durationHours);
    }

    function setCourseActive(string calldata courseCode, bool active) external onlyOwner {
        require(courses[courseCode].exists, "Course not found");
        courses[courseCode].active = active;
        emit CourseStatusChanged(courseCode, active);
    }

    function getCourse(string calldata courseCode) external view returns (Course memory) {
        require(courses[courseCode].exists, "Course not found");
        return courses[courseCode];
    }

    function getAllCourses() external view returns (Course[] memory list) {
        list = new Course[](courseCodes.length);
        for (uint256 i = 0; i < courseCodes.length; i++) {
            list[i] = courses[courseCodes[i]];
        }
    }

    // ------------------------------------------------------------------
    // 2) Issue Certificate  +  3) Store Certificate Hash
    // ------------------------------------------------------------------
    function issueCertificate(
        string calldata certId,
        string calldata courseCode,
        address recipient,
        bytes32 recipientHash,
        bytes32 documentHash,
        uint64 issueDate
    ) external onlyIssuer {
        require(bytes(certId).length > 0, "Certificate ID required");
        require(!certificates[certId].exists, "Certificate ID already exists");
        require(courses[courseCode].exists, "Course not found");
        require(courses[courseCode].active, "Course is inactive");
        require(recipient != address(0), "Invalid recipient wallet");
        require(recipientHash != bytes32(0), "Recipient hash required");
        require(documentHash != bytes32(0), "Document hash required");
        require(bytes(documentHashToCertId[documentHash]).length == 0, "Document already registered");

        certificates[certId] = Certificate({
            certId: certId,
            courseCode: courseCode,
            recipient: recipient,
            recipientHash: recipientHash,
            documentHash: documentHash,
            issueDate: issueDate == 0 ? uint64(block.timestamp) : issueDate,
            recordedAt: uint64(block.timestamp),
            issuer: msg.sender,
            revoked: false,
            revokedAt: 0,
            revokeReason: "",
            exists: true
        });

        certIds.push(certId);
        recipientCerts[recipient].push(certId);
        documentHashToCertId[documentHash] = certId;

        emit CertificateIssued(certId, courseCode, recipient, documentHash, msg.sender);
    }

    // ------------------------------------------------------------------
    // 4) Verify Certificate
    // ------------------------------------------------------------------
    /// @notice ตรวจสอบสถานะด้วยรหัสใบรับรอง (ใช้กับการค้นหา / สแกน QR)
    function verifyCertificate(string calldata certId)
        external
        view
        returns (Status status, Certificate memory cert, Course memory course)
    {
        cert = certificates[certId];
        if (!cert.exists) {
            return (Status.NotFound, cert, course);
        }
        course = courses[cert.courseCode];
        status = cert.revoked ? Status.Revoked : Status.Valid;
    }

    /// @notice ตรวจว่าไฟล์ที่ได้รับตรงกับ hash ที่บันทึกไว้หรือไม่ (ตรวจการแก้ไขเอกสาร)
    function verifyDocument(string calldata certId, bytes32 documentHash)
        external
        view
        returns (bool hashMatches, Status status)
    {
        Certificate storage c = certificates[certId];
        if (!c.exists) return (false, Status.NotFound);
        return (c.documentHash == documentHash, c.revoked ? Status.Revoked : Status.Valid);
    }

    /// @notice ค้นหาใบรับรองจาก hash ของไฟล์โดยตรง (กรณีมีแต่ไฟล์)
    function findByDocumentHash(bytes32 documentHash) external view returns (string memory) {
        return documentHashToCertId[documentHash];
    }

    // ------------------------------------------------------------------
    // 5) Revoke Certificate (คงประวัติไว้ ไม่ลบข้อมูล)
    // ------------------------------------------------------------------
    function revokeCertificate(string calldata certId, string calldata reason) external onlyIssuer {
        Certificate storage c = certificates[certId];
        require(c.exists, "Certificate not found");
        require(!c.revoked, "Already revoked");
        require(bytes(reason).length > 0, "Reason required");

        c.revoked = true;
        c.revokedAt = uint64(block.timestamp);
        c.revokeReason = reason;

        emit CertificateRevoked(certId, reason, msg.sender);
    }

    // ------------------------------------------------------------------
    // 6) Certificate Dashboard
    // ------------------------------------------------------------------
    function getCertificate(string calldata certId) external view returns (Certificate memory) {
        require(certificates[certId].exists, "Certificate not found");
        return certificates[certId];
    }

    function getCertificateIdsOf(address recipient) external view returns (string[] memory) {
        return recipientCerts[recipient];
    }

    function getCertificatesOf(address recipient) external view returns (Certificate[] memory list) {
        string[] storage ids = recipientCerts[recipient];
        list = new Certificate[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            list[i] = certificates[ids[i]];
        }
    }

    function getAllCertificateIds() external view returns (string[] memory) {
        return certIds;
    }

    function totalCertificates() external view returns (uint256) {
        return certIds.length;
    }

    function totalCourses() external view returns (uint256) {
        return courseCodes.length;
    }
}
