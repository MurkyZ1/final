# SkillTrust Academy — ระบบออกและตรวจสอบใบรับรองดิจิทัล (Blockchain)

```
skilltrust/
├── contracts/
│   ├── SkillTrustCertificate.sol        ← Smart Contract (นำไปวางใน Remix)
│   └── SkillTrustCertificate.abi.json   ← ABI (ฝังไว้ใน frontend แล้ว)
└── frontend/
    └── index.html                       ← หน้าเว็บ (ไฟล์เดียว ใช้ ethers.js + MetaMask)
```

## 1. Deploy Smart Contract ด้วย Remix

1. เปิด https://remix.ethereum.org → สร้างไฟล์ `SkillTrustCertificate.sol` แล้ววางโค้ดจาก `contracts/`
2. แท็บ **Solidity Compiler** → เลือกเวอร์ชัน `0.8.20` ขึ้นไป → กด **Compile**
3. แท็บ **Deploy & Run Transactions**
   - **Environment:** เลือก `Injected Provider - MetaMask` (แนะนำเครือข่าย **Sepolia Testnet** — ขอ SepoliaETH ฟรีจาก faucet)
   - กด **Deploy** → ยืนยันใน MetaMask
4. คัดลอก **Contract Address** ใต้ "Deployed Contracts"

> ⚠️ ถ้าเลือก `Remix VM` ทดสอบได้เฉพาะใน Remix เท่านั้น หน้าเว็บจะเชื่อมต่อไม่ได้
> ถ้าอยากทดสอบในเครื่อง ให้ใช้ Ganache / Hardhat node แล้วเลือก `Dev - Ganache Provider` หรือเพิ่มเครือข่าย localhost ใน MetaMask

บัญชีที่กด Deploy จะเป็น **ผู้ดูแลระบบ (Admin)** และเป็น Issuer โดยอัตโนมัติ

## 2. เปิด Frontend

MetaMask ไม่ทำงานกับไฟล์ที่เปิดแบบ `file://` จึงต้องเปิดผ่าน web server:

```bash
cd frontend
npx serve .          # หรือ python3 -m http.server 8080
```
หรือใช้ส่วนขยาย **Live Server** ใน VS Code แล้วเปิด `index.html`

จากนั้น: กด **เชื่อมต่อ MetaMask** → วาง Contract Address ในแถบ **ตั้งค่า** → บันทึก

## 3. ลำดับการทดสอบ (Demo Flow)

| ขั้น | เมนู | ทำอะไร | ใครทำได้ |
|---|---|---|---|
| 1 | 📚 หลักสูตร | สร้างหลักสูตร เช่น `AI-101` | Admin |
| 2 | ⚙️ ผู้ดูแลระบบ | เพิ่ม Wallet อื่นเป็น Issuer (ไม่บังคับ) | Admin |
| 3 | ✍️ ออกใบรับรอง | กรอกรหัส, เลือกหลักสูตร, ชื่อ, Wallet ผู้รับ, แนบไฟล์ PDF → บันทึก → ได้ QR Code | Admin / Issuer |
| 4 | 🔍 ตรวจสอบ | ค้นด้วยรหัส / สแกน QR / แนบไฟล์เพื่อตรวจว่าถูกแก้ไขหรือไม่ / พิมพ์ชื่อเพื่อยืนยันผู้รับ | ทุกคน |
| 5 | ⛔ เพิกถอน | ใส่รหัส + เหตุผล → สถานะเปลี่ยนเป็น "ถูกเพิกถอน" (ประวัติยังอยู่) | Admin / Issuer |
| 6 | 📂 ใบรับรองของฉัน | สลับ MetaMask ไปเป็น Wallet ผู้รับ → ดูรายการใบรับรอง | ผู้เข้าอบรม |

**ลองทดสอบการปลอมแปลง:** แก้ไขไฟล์ PDF เล็กน้อย (เช่น เปลี่ยนชื่อ) แล้วนำไปตรวจในหน้า "ตรวจสอบ" → ระบบจะแจ้ง "ไฟล์ไม่ตรง — อาจถูกแก้ไข"

## 4. การออกแบบตามกฎทางธุรกิจ

| กฎ | วิธีที่ทำในระบบ |
|---|---|
| รหัสใบรับรองห้ามซ้ำ | `require(!certificates[certId].exists)` และไฟล์เดียวกันห้ามลงทะเบียนซ้ำ (`documentHashToCertId`) |
| ผู้ไม่ได้รับอนุญาตห้ามออก/เพิกถอน | `modifier onlyIssuer` / `onlyOwner` + ระบบจัดการ Issuer |
| ไม่นำข้อมูลส่วนบุคคลขึ้น Public Blockchain | เก็บแค่ `recipientHash = keccak256(ชื่อ | certId)` และ `documentHash = keccak256(ไฟล์)` — ชื่อจริงอยู่บนตัวเอกสารเท่านั้น ผู้ตรวจพิมพ์ชื่อเพื่อเทียบ hash ได้ |
| เพิกถอนแต่คงประวัติ | ไม่ลบข้อมูล เปลี่ยน `revoked = true` + บันทึก `revokedAt`, `revokeReason` และ emit event |
| ตรวจว่าเอกสารไม่ถูกแก้ไข | คำนวณ keccak256 ของไฟล์ในเบราว์เซอร์ แล้วเทียบกับ `documentHash` บนเชน |

## 5. ฟังก์ชันหลักใน Contract

| ฟังก์ชัน | ข้อกำหนด |
|---|---|
| `createCourse(code, name, description, hours)` | 1. ลงทะเบียนหลักสูตร |
| `issueCertificate(certId, courseCode, recipient, recipientHash, documentHash, issueDate)` | 2. ออกใบรับรอง + 3. บันทึก Hash |
| `verifyCertificate(certId)` → `(status, cert, course)` | 4. ตรวจสอบ (0=ไม่พบ, 1=ใช้งานได้, 2=เพิกถอน) |
| `verifyDocument(certId, hash)` / `findByDocumentHash(hash)` | 4. ตรวจไฟล์ |
| `revokeCertificate(certId, reason)` | 5. เพิกถอน |
| `getCertificatesOf(wallet)` | 6. Dashboard |
| `addIssuer` / `removeIssuer` / `transferOwnership` | จัดการสิทธิ์ |

> หมายเหตุ: ถ้าไม่แนบไฟล์ตอนออกใบรับรอง ระบบจะใช้ hash ของข้อมูลใบรับรอง (certId + หลักสูตร + recipientHash + วันที่) แทน เพื่อให้ demo ได้แม้ไม่มีไฟล์ PDF
