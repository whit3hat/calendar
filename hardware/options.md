# Hardware Options — Raspberry Pi Wall Calendar

Three options per component, ordered from most accessible to most powerful.
Prices are USD estimates as of early 2025 — check linked retailers for current pricing.

---

## 1. Single-Board Computer (SBC)

The brain of the calendar. Needs WiFi, enough RAM to run a smooth touch UI, and reliable 24/7 operation.

### Option A — Raspberry Pi 4 Model B (4GB)
**Estimated price:** ~$55 MSRP
**Buy:** [raspberrypi.com](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/) · [CanaKit](https://www.canakit.com/raspberry-pi-4-4gb.html) · [Amazon](https://www.amazon.com/raspberry-pi-4-4gb/s?k=raspberry+pi+4+4gb) · [Adafruit](https://www.adafruit.com)

| Spec | Value |
|---|---|
| CPU | Broadcom BCM2711 Cortex-A72, quad-core 1.5 GHz |
| RAM | 4GB LPDDR4 |
| GPU | VideoCore VI (OpenGL ES 3.0) |
| WiFi | 802.11ac dual-band |
| Ports | 2× USB 3.0, 2× USB 2.0, 2× micro-HDMI |
| Power draw | ~3–5W typical |

**Pros:**
- Largest community, most tutorials, most Pi-compatible accessories
- Rock-solid 24/7 reliability record
- Low power draw, runs cool
- Excellent MagicMirror² and kiosk-mode documentation for this exact use case
- Most accessories (HATs, cases, UPS boards) designed with Pi 4 in mind

**Cons:**
- Slower than Pi 5 — animations/scrolling can feel slightly less smooth
- Uses micro-HDMI (requires adapter/specific cable for most monitors)
- USB boot requires a firmware update (microSD works out of the box)
- Lower GPU performance than Pi 5 or Orange Pi options

---

### Option B — Raspberry Pi 5 (4GB or 8GB)
**Estimated price:** ~$60 (4GB) / ~$80 (8GB) MSRP
**Buy:** [raspberrypi.com](https://www.raspberrypi.com/products/raspberry-pi-5/) · [CanaKit](https://www.canakit.com) · [Adafruit](https://www.adafruit.com) · [Pimoroni](https://shop.pimoroni.com)

| Spec | Value |
|---|---|
| CPU | Broadcom BCM2712 Cortex-A76, quad-core 2.4 GHz |
| RAM | 4GB or 8GB LPDDR5X |
| GPU | VideoCore VII (improved over Pi 4) |
| WiFi | 802.11ac dual-band |
| Ports | 2× USB 3.0, 2× USB 2.0, 2× full-size HDMI |
| Power draw | ~5–8W typical |

**Pros:**
- ~60% faster than Pi 4 — noticeably smoother touch UI
- Full-size HDMI ports (no adapter needed)
- Native USB SSD boot support
- PCIe connector for NVMe HATs (fastest storage option available)
- 8GB option is extremely future-proof
- Better thermal management design

**Cons:**
- More expensive than Pi 4
- Requires a 5A USB-C PSU (official one recommended — underpowering causes throttling)
- Slightly higher power consumption
- Some older HATs not compatible without adapter

**Recommendation:** Best all-around choice for this project if budget allows.

---

### Option C — Orange Pi 5 (4GB)
**Estimated price:** ~$65–85
**Buy:** [Amazon](https://www.amazon.com/Orange-Pi-Frequency-Development-Android12/dp/B0BN16ZLXB) · [AliExpress](https://www.aliexpress.com) (search "Orange Pi 5 4GB")

| Spec | Value |
|---|---|
| CPU | Rockchip RK3588S, octa-core Cortex-A76/A55, 2.4 GHz |
| RAM | 4GB LPDDR4 (8GB/16GB options exist) |
| GPU | Mali-G610MP4 (significantly stronger than Pi) |
| WiFi | Onboard WiFi 5 (some variants — verify before buying) |
| Ports | HDMI 2.1, USB-C DisplayPort alt mode, USB 3.0 |
| Power draw | ~8–10W typical |

**Pros:**
- Much stronger GPU — very smooth UI rendering and animations
- Supports HDMI 2.1 and 4K output
- More RAM options up to 16GB
- Better for complex UIs or future expansion

**Cons:**
- Smaller community than Raspberry Pi — less documentation for calendar projects
- Not all Raspberry Pi-specific software/HATs are compatible
- WiFi not always included on base model (verify before ordering)
- Harder to find in some regions; supply less reliable
- Some driver/compatibility quirks vs. RPi OS ecosystem

---

## 2. Touchscreen Display

The most important aesthetic and usability component. IPS panels are mandatory for wall mounting (wide viewing angles). Capacitive touch only — resistive panels are inferior for multi-touch and feel outdated.

### Option A — Waveshare 10.1" HDMI IPS Capacitive Touch (with Case)
**Estimated price:** ~$85–100
**Buy:** [Waveshare official](https://www.waveshare.com/10.1inch-hdmi-lcd-with-case.htm) · [Amazon](https://www.amazon.com/10-1inch-HDMI-LCD-case-Touchscreen/dp/B01H013FGC)

| Spec | Value |
|---|---|
| Size | 10.1 inches |
| Resolution | 1280×800 IPS |
| Touch | 10-point capacitive, 6H toughened glass |
| Connection | HDMI + USB (for touch) |
| Compatibility | Driver-free on Raspberry Pi OS, also supports Windows/Ubuntu |

**Pros:**
- Plug-and-play on Raspberry Pi OS — no driver installation required
- IPS panel gives great viewing angles for wall mount
- Toughened glass is durable for daily touch use
- Comes with protective case (some versions)
- Well-documented community support for Pi projects
- Portable enough to prototype on a desk before mounting

**Cons:**
- 1280×800 is good but not full HD — text looks slightly less crisp than 1080p
- Separate power required for display (USB-C or barrel jack)
- Bezel is functional but not the most elegant
- 10.1" may feel compact for a full monthly calendar view

---

### Option B — SunFounder 10" All-in-One IPS Touchscreen (for Raspberry Pi 5)
**Estimated price:** ~$150
**Buy:** [SunFounder official](https://www.sunfounder.com/products/10inch-touchscreen-for-raspberrypi) · [Amazon](https://www.amazon.com/SunFounder-Raspberry-1280x800-10-Point-Speakers/dp/B0776VNW9C)

| Spec | Value |
|---|---|
| Size | 10 inches |
| Resolution | 1280×800 IPS |
| Touch | 10-point capacitive |
| Connection | HDMI + built-in USB-C PD 5.1V/5A output for Pi |
| Extras | Dual built-in speakers, 178° viewing angle |

**Pros:**
- Built-in USB-C PD output powers the Raspberry Pi directly — one less cable, one less PSU to buy
- Dual speakers built in (useful for notification sounds or ambient audio)
- 178° IPS viewing angle — excellent for wall mounting at various heights
- Driver-free, plug-and-play on latest Raspberry Pi OS
- Great build quality for a polished wall-mount look
- Reviewed positively for calendar and MagicMirror projects specifically ([Gadgeteer review](https://the-gadgeteer.com/2025/04/09/sunfounder-raspberry-pi-10-inch-diy-touch-screen-review/))

**Cons:**
- Most expensive display option at ~$150
- Same 1280×800 resolution as cheaper alternatives
- 10" may still feel compact depending on how many events you display

**Recommendation:** Best display for a clean, low-cable-count build. The built-in Pi power passthrough is a standout feature.

---

### Option C — Waveshare 13.3" HDMI IPS Capacitive Touch V2 (with Case)
**Estimated price:** ~$110–130
**Buy:** [Amazon V2](https://www.amazon.com/waveshare-13-3inch-Capacitive-LCD-HDMI/dp/B0B1GT1K5R) · [Waveshare official](https://www.waveshare.com/13.3inch-hdmi-lcd-h-with-case-v2.htm)

| Spec | Value |
|---|---|
| Size | 13.3 inches |
| Resolution | 1920×1080 Full HD IPS |
| Touch | 10-point capacitive, 6H toughened glass |
| Connection | HDMI + USB (for touch) |
| Compatibility | Driver-free on Raspberry Pi OS |

**Pros:**
- Full HD 1920×1080 — calendar text and event details are noticeably crisper
- Larger canvas — shows a full month view comfortably
- Still reasonably priced for a 13.3" IPS touchscreen
- IPS viewing angles ideal for wall mount
- Toughened glass, durable for regular touch use
- Looks like a proper wall-mounted calendar at this size

**Cons:**
- Requires its own power supply separate from the Pi (two wall adapters)
- Larger footprint requires a more substantial wall mount
- Slightly harder to find a polished enclosure/frame vs. smaller options

**Recommendation:** Best display if readability and a "real calendar" feel are top priorities.

---

## 3. Power Supply

The PSU is often the source of instability in Pi projects. Cheap PSUs cause undervoltage warnings, random reboots, and corrupted SD cards. Don't cut corners here.

### Option A — Official Raspberry Pi USB-C Power Supply
**Estimated price:** ~$12 (Pi 4 3A) / ~$16 (Pi 5 5A)
**Buy:** [raspberrypi.com](https://www.raspberrypi.com/products/type-c-power-supply/) · [Adafruit](https://www.adafruit.com) · [Amazon](https://www.amazon.com/Raspberry-Pi-USB-C-Power-Supply/dp/B07W8XHMJZ)

**Pros:**
- Guaranteed compatibility — no guessing on voltage stability
- Compact, no noise on power rail
- Pi 5 version (5A) handles peak loads without throttling

**Cons:**
- Pi 4 3A version may show undervoltage if you add many USB peripherals
- No battery backup
- Short cable on some versions

---

### Option B — CanaKit 3.5A Premium USB-C Power Supply
**Estimated price:** ~$14–20
**Buy:** [CanaKit](https://www.canakit.com/raspberry-pi-4-power-supply.html) · [Amazon](https://www.amazon.com/s?k=canakit+raspberry+pi+power+supply)

**Pros:**
- Slightly higher current output than official (3.5A vs 3A for Pi 4)
- Well-reviewed for 24/7 continuous use
- Longer cable (6 ft) — easier to route for wall installations

**Cons:**
- Not rated for Pi 5 (need 5A for Pi 5)
- Third-party, though highly reputable

---

### Option C — Raspberry Pi PoE+ HAT
**Estimated price:** ~$35–40 (HAT) + requires a PoE-capable switch/router (~$30–80 for basic)
**Buy:** [Official Pi PoE+ HAT](https://www.raspberrypi.com/products/poe-plus-hat/) · [Adafruit](https://www.adafruit.com) · [Amazon](https://www.amazon.com/s?k=raspberry+pi+poe+hat)

**Pros:**
- One single cable (Ethernet) handles both power and network
- No USB-C PSU needed at the Pi — cleaner wall installation
- Very reliable for 24/7 — no adapter to fail
- Eliminates one cable run to the wall mount

**Cons:**
- Requires a PoE-capable network switch or router (adds $30–80+ if you don't have one)
- HAT occupies GPIO header — may conflict with some UPS HATs
- Higher total upfront cost
- Ethernet cable needs to reach the wall mount location

---

## 4. Storage

MicroSD cards wear out under constant read/write cycles. For a 24/7 device, use either a high-endurance card or move to SSD boot.

### Option A — Samsung PRO Endurance microSD (128GB)
**Estimated price:** ~$25–35
**Buy:** [Amazon](https://www.amazon.com/s?k=samsung+pro+endurance+microsd+128gb) · [B&H Photo](https://www.bhphotovideo.com)

**Pros:**
- Purpose-built for 24/7 continuous recording (security cameras, dashcams)
- Rated for ~43,800 hours of continuous operation
- No extra hardware needed — plug in and go
- Lower power than SSD

**Cons:**
- Still slower than SSD for reads/writes
- Finite write cycles — will eventually fail (just more slowly than standard cards)
- 128GB is overkill for a calendar app but future-proofs storage

---

### Option B — Samsung T7 Portable USB SSD (500GB)
**Estimated price:** ~$50–65
**Buy:** [Amazon](https://www.amazon.com/s?k=samsung+t7+500gb) · [Best Buy](https://www.bestbuy.com) · [B&H Photo](https://www.bhphotovideo.com)

**Pros:**
- Much higher endurance than any microSD
- Dramatically faster boot and app loading
- Shock-resistant enclosure
- Pi 5 boots from USB natively; Pi 4 requires a one-time firmware update
- Small form factor, easy to tuck behind display

**Cons:**
- Higher cost than microSD
- Uses a USB 3.0 port
- Still requires a microSD with bootloader on Pi 4 (just the initial setup)

---

### Option C — Pimoroni NVMe Base + Samsung 980 NVMe SSD (Pi 5 only)
**Estimated price:** ~$30–35 (HAT) + ~$40–50 (SSD) = ~$70–85 total
**Buy:** [Pimoroni NVMe Base](https://shop.pimoroni.com/products/nvme-base) · [Samsung 980 on Amazon](https://www.amazon.com/s?k=samsung+980+500gb+nvme)

**Pros:**
- Fastest possible storage for Pi 5 (PCIe Gen 2 × 1)
- Exceptional endurance — NVMe SSDs last many years of 24/7 use
- Keeps USB ports free
- Passive cooling built into Pimoroni base

**Cons:**
- **Pi 5 only** — will not work on Pi 4
- Highest cost option
- Overkill for a calendar display but excellent long-term reliability
- Takes up the HAT space on the Pi

---

## 5. UPS / Battery Backup

A UPS protects the Pi from sudden power cuts that can corrupt the filesystem. For a wall calendar, the goal isn't long runtime — just enough for a graceful shutdown.

### Option A — PiSugar S3
**Estimated price:** ~$35–50
**Buy:** [Amazon](https://www.amazon.com/s?k=pisugar+s3) · [PiSugar official store](https://www.pisugar.com) · [Pimoroni](https://shop.pimoroni.com)

**Pros:**
- Most compact UPS HAT — minimal size impact
- Includes RTC (real-time clock) — keeps time accurate even without internet
- Web dashboard for battery monitoring and configuring auto-shutdown
- ~20–30 min runtime (more than enough for graceful shutdown)
- Active development and community

**Cons:**
- Small battery (850mAh) — not for extended outages
- Battery degrades over 2–3 years
- Full features require a Python daemon running on the Pi
- Some reported compatibility issues with certain GPIO HAT stacks

---

### Option B — Waveshare UPS HAT+
**Estimated price:** ~$30–45
**Buy:** [Waveshare official](https://www.waveshare.com) · [Amazon](https://www.amazon.com/s?k=waveshare+ups+hat) · [AliExpress](https://www.aliexpress.com)

**Pros:**
- Larger battery (1500–2000mAh) → ~45–60 min runtime
- Multiple USB output ports (can power other devices during outage)
- Lower price per mAh than PiSugar
- Works with Pi 4 and Pi 5

**Cons:**
- Bulkier than PiSugar — takes more HAT space
- RTC not always included (check specific model)
- Software support less polished than PiSugar
- Some quality inconsistencies reported in older batches

---

### Option C — Geekworm X728 / X734
**Estimated price:** ~$40–65
**Buy:** [Amazon](https://www.amazon.com/s?k=geekworm+x728) · [AliExpress](https://www.aliexpress.com) · [Geekworm store](https://geekworm.com)

**Pros:**
- Industrial build quality with metal housing
- Integrated RTC included
- Built-in safe-shutdown button (hardware-level protection)
- X734 variant has 5000mAh capacity (extended outage protection)
- Reliable for 24/7 use

**Cons:**
- Bulkiest option — significantly adds to enclosure thickness
- X734 is expensive for a calendar project
- Older firmware/documentation than competitors
- Requires Linux daemon for full features

---

## 6. Enclosure / Wall Mount

The enclosure determines how polished the final product looks on your wall.

### Option A — VESA-Mount Touchscreen + Pi Bracket (Recommended for 13.3")
**Estimated price:** ~$15–35 for the Pi bracket (display cost separate)
**Buy:** Search "Raspberry Pi VESA mount bracket" on [Amazon](https://www.amazon.com/s?k=raspberry+pi+vesa+mount) · Various brands

**How it works:** Mount a VESA-compatible touchscreen to the wall, then attach a small Pi VESA bracket to the back of the monitor. Pi mounts cleanly out of sight.

**Pros:**
- Works with any VESA 75/100 compatible display (most 13"+ screens)
- Professional, clean look — looks like a mounted screen
- Display and Pi upgradeable independently
- Many display + bracket combos work out of the box
- Good cable management behind the screen

**Cons:**
- Two power cables still needed (display + Pi, unless using SunFounder's built-in Pi power)
- VESA bracket quality varies — buy one with good reviews
- Requires wall anchoring appropriate for screen weight

---

### Option B — DIY Picture Frame Enclosure
**Estimated price:** ~$20–50 for frame (IKEA, Michaels, or similar)
**Buy:** [IKEA](https://www.ikea.com) (look for RIBBA or SANNAHED frames) · [Amazon](https://www.amazon.com/s?k=deep+picture+frame+shadow+box) · craft stores

**How it works:** A deep shadow box or picture frame is cut/modified to fit the display, with the Pi tucked in the back and a clean glass or acrylic front.

**Pros:**
- Looks like a piece of art on the wall — very natural aesthetic
- Cheap
- Easily customizable size and color/finish
- Widely available

**Cons:**
- Requires DIY fabrication (measuring, cutting, drilling)
- Heat management needs planning — Pi needs ventilation
- Not designed for touchscreens — frame may block touch area at edges
- Looks rough if not executed carefully

---

### Option C — 3D-Printed Custom Frame
**Estimated price:** ~$0–20 in filament if you own a printer; ~$40–100 via a printing service
**Find designs:** [Printables.com](https://www.printables.com) (search "Raspberry Pi wall mount frame") · [Thingiverse.com](https://www.thingiverse.com) (search "Pi touchscreen enclosure")

**How it works:** Download a community-designed frame or design your own in Fusion 360 / FreeCAD, sized exactly to your display. Print in PLA or PETG.

**Pros:**
- Fully customizable — exact fit for your display and Pi
- Can include integrated cable channels, ventilation slots, magnetic mounting
- Low material cost if you own a printer
- Large library of existing designs on Printables/Thingiverse

**Cons:**
- Requires a 3D printer or paying a printing service
- Large prints (13"+) can warp or have layer adhesion issues
- Requires post-processing (sanding, painting) for a polished look
- Design quality varies significantly — vet designs before printing

---

## 7. Large Touchscreen Displays (15"+)

For a wall calendar that genuinely reads like a physical calendar, 15"+ is where it starts to feel natural. These are all direct HDMI + USB touchscreen monitors compatible with Raspberry Pi — no extra adapters needed.

> **Note on the 21.5" Waveshare orientation:** The 21.5" model ships configured for portrait (1080×1920) use. It can be rotated to landscape in software, but verify your enclosure/wall mount supports landscape orientation before ordering.

### Option A — Waveshare 15.6" HDMI IPS Capacitive Touch (with Case)
**Estimated price:** ~$85–100
**Buy:** [Waveshare official](https://www.waveshare.com/15.6inch-hdmi-lcd-h-with-case.htm) · [Amazon](https://www.amazon.com/15-6inch-HDMI-LCD-case-Resolution/dp/B07QXKKHRF)

| Spec | Value |
|---|---|
| Size | 15.6 inches |
| Resolution | 1920×1080 Full HD IPS |
| Touch | 10-point capacitive, 6H toughened glass |
| Connection | HDMI + USB (for touch) |
| Compatibility | Driver-free on Raspberry Pi OS, Ubuntu, Windows |

**Pros:**
- Full HD 1920×1080 at a size that comfortably shows a full month view
- Familiar laptop-screen form factor — easy to find wall mounts and VESA brackets
- Most affordable step-up from 13.3" at similar price point
- IPS panel, wide viewing angle, no color shift from off-axis
- Driver-free on Raspberry Pi OS

**Cons:**
- Requires separate power supply for the display (two cables to manage)
- Thinner bezel means less room to work with for custom framing
- At 15.6" the VESA mount options narrow vs. smaller screens — verify before buying

---

### Option B — Waveshare 21.5" Capacitive Touch Monitor
**Estimated price:** ~$220
**Buy:** [Amazon](https://www.amazon.com/Waveshare-21-5inch-Capacitive-Compatible-Raspberry/dp/B0D6FTG8X8) · [Waveshare official](https://www.waveshare.com/product/raspberry-pi/displays.htm)

| Spec | Value |
|---|---|
| Size | 21.5 inches |
| Resolution | 1920×1080 Full HD |
| Touch | 10-point capacitive |
| Connection | HDMI + USB (for touch) |
| Compatibility | Raspberry Pi 5/4B/3B/Zero, Jetson Nano, Windows |

**Pros:**
- Closest to a physical wall calendar in size — genuinely feels like a real appliance
- Large enough to show multiple months or week view with full event detail at a glance
- 21.5" is standard monitor territory — wall mounts and VESA hardware are widely available
- Text and event names legible from across a room

**Cons:**
- Most expensive display option at ~$220
- Ships in portrait orientation by default — confirm software rotation support for your UI
- Requires its own power brick + HDMI cable (plan cable routing carefully)
- Larger thermal footprint means the Pi enclosure needs adequate ventilation

---

### Option C — DFRobot 16" 4K OLED Touchscreen
**Estimated price:** ~$300–400 (check current price — verify at product page)
**Buy:** [DFRobot official](https://www.dfrobot.com/product-2859.html)

| Spec | Value |
|---|---|
| Size | 16 inches |
| Resolution | 3840×2400 (4K, 16:10 aspect ratio) |
| Panel type | Samsung OLED |
| Touch | 10-point capacitive |
| Connection | HDMI + Type-C |
| Compatibility | Raspberry Pi 4B/5, LattePanda, NVIDIA SBCs, PS5, Xbox, Switch |

**Pros:**
- Samsung OLED panel — vastly better contrast, color depth, and blacks vs. any IPS option
- 4K at 16" means text is razor sharp — event names and details are extremely crisp
- Thinnest form factor of any option — looks premium mounted on a wall
- Built-in speakers
- Type-C alt-mode input in addition to HDMI

**Cons:**
- Most expensive display option by a significant margin
- OLED panels can experience burn-in over time — a static calendar UI (always-on) is a risk; a screensaver or scheduled display-off is essential
- 4K output at full resolution requires Pi 5 to drive smoothly (Pi 4 may struggle)
- Harder to find compatible enclosures at this size
- Less community documentation for Pi at this resolution

---

## 8. Touchscreen Overlays / Digitizers

An overlay is a frame or panel that sits in front of any existing LCD monitor and adds touch capability. This approach lets you use a larger or higher-quality monitor you already own (or buy cheaply) and add touch on top. There are two practical overlay technologies for DIY builds.

> **Critical compatibility note:** Always verify that the overlay lists **"HID compliant"** and **"driver-free / Linux compatible"** before purchasing. Some brands (notably GreenTouch) explicitly do not support Raspberry Pi despite being marketed as plug-and-play. Look for products that list Linux or Raspberry Pi in their compatibility list.

### Option A — USB IR Touch Frame Overlay (SPECIAL PIE / Generic HID)
**Estimated price:** ~$50–100 for 19–22" sizes
**Buy:** [Amazon — SPECIAL PIE 32"](https://www.amazon.com/PIE-Point-Multi-Touch-Infrared-Touch/dp/B07Y1R35S6) (search "IR touch frame overlay [size] HID Linux" for your exact size) · [Newegg](https://www.newegg.com/p/pl?d=touch+screen+overlay) · [AliExpress](https://www.aliexpress.com)

**How it works:** A rectangular frame with IR LED emitters and receivers along its edges mounts around the bezel of your monitor. A finger crossing the invisible IR grid registers a touch. Connects to the Pi via USB as a standard HID pointer device — no drivers needed.

| Spec | Value |
|---|---|
| Compatible monitor sizes | 15"–86"+ (buy the size matching your monitor) |
| Touch points | 2–10 point multi-touch (varies by model) |
| Connection | USB (HID — plug and play on Linux) |
| Thickness added | ~8–12mm frame around monitor edges |

**Pros:**
- Works with virtually any existing LCD, IPS, or even old CRT monitor
- Available in sizes up to 86"+ — not limited to 15" or 21"
- Relatively affordable — a 19–21" frame costs $50–100
- Plug-and-play HID on Linux (Raspberry Pi OS recognizes it as a USB mouse/touch device)
- No modifications to the monitor required
- Easy to replace if damaged

**Cons:**
- Adds a visible frame border around your monitor edges (8–12mm wide)
- Touch accuracy not as precise as capacitive glass — slight parallax at edges
- IR can be confused by very bright direct sunlight hitting the screen
- Frame needs precise size match — a 19" overlay won't fit a 21" monitor
- Some cheap frames have poor build quality; read reviews carefully
- **Not all brands support Raspberry Pi — always verify Linux/HID compatibility**

---

### Option B — ELO Touch or Tyco Touch PCAP Glass Overlay (Professional Grade)
**Estimated price:** ~$200–600+ depending on size
**Buy:** [TycoTouch](https://tycotouch.com) · [ELO Touch](https://www.elotouch.com) · search "PCAP touch overlay [size]"

**How it works:** A thin tempered glass panel with a projected capacitive (PCAP) grid is mounted flush over the monitor glass. Connects via USB. Feels identical to a modern smartphone or tablet touchscreen.

| Spec | Value |
|---|---|
| Touch technology | PCAP (projected capacitive) |
| Touch points | 10–20 point multi-touch |
| Connection | USB HID |
| OS support | Windows, macOS, Linux (including Raspberry Pi) |

**Pros:**
- Touch quality identical to a premium capacitive smartphone screen
- No visible added frame — glass sits flush on the monitor face
- Excellent multi-touch accuracy across the entire surface, including edges
- Industrial/commercial grade — built for 24/7 operation
- Works reliably in all lighting conditions (no IR interference)
- TycoTouch explicitly lists Raspberry Pi and Linux in their compatibility ([tycotouch.com](https://tycotouch.com/products/27-inch-magic-touch-screen-overlay-kit))

**Cons:**
- Significantly more expensive than IR frames ($200–600+)
- Sizing must be exact — custom-ordered for specific monitor dimensions
- Primarily sold for commercial/industrial applications; consumer support is limited
- Adds slight glass thickness (~3–5mm) between finger and display
- Typically requires professional installation for best results

---

### Option C — Buy a Purpose-Built Large Touchscreen Monitor
**Estimated price:** ~$150–350 for 21–24" consumer touchscreen monitors
**Buy:** Search "21 inch touchscreen monitor USB HDMI" on [Amazon](https://www.amazon.com/s?k=21+inch+touchscreen+monitor+HDMI) · [Newegg](https://www.newegg.com)

**How it works:** Instead of adding an overlay to a separate display, buy a monitor that has capacitive touch built into the glass from the factory. Many commercial 21"–24" touchscreen monitors exist at consumer prices and connect via HDMI + USB just like the Waveshare/SunFounder displays.

**Pros:**
- Touch and display are factory-integrated — no alignment issues, no parallax, no separate frame
- Wider availability in 21"–24" sizes vs. Pi-specific displays
- Often VESA-mountable with standard wall-mount hardware
- Capacitive touch quality is excellent
- More monitor choices at this size than Pi-specific options

**Cons:**
- Need to verify Linux/Raspberry Pi driver support before buying — not all consumer touchscreen monitors advertise Pi compatibility
- May require manually configuring touch calibration on Raspberry Pi OS
- Often require separate USB-C or USB-A touch cable in addition to HDMI
- Cheaper consumer monitors may use resistive touch (inferior) — verify it's capacitive

---

## Suggested Combinations

### Budget Build (~$250–300 total)
| Component | Choice |
|---|---|
| SBC | Raspberry Pi 4 Model B 4GB |
| Display | Waveshare 10.1" HDMI IPS |
| Power | Official Raspberry Pi USB-C PSU (3A) |
| Storage | Samsung PRO Endurance 128GB microSD |
| UPS | PiSugar S3 |
| Enclosure | Picture frame DIY |

### Recommended Build (~$380–450 total)
| Component | Choice |
|---|---|
| SBC | Raspberry Pi 5 (4GB) |
| Display | SunFounder 10" All-in-One (powers Pi via built-in output) |
| Power | Built into SunFounder display (one PSU total) |
| Storage | Samsung T7 USB SSD 500GB |
| UPS | Waveshare UPS HAT+ |
| Enclosure | VESA bracket on back of display |

### Premium Build (~$500–600 total)
| Component | Choice |
|---|---|
| SBC | Raspberry Pi 5 (8GB) |
| Display | Waveshare 13.3" HDMI IPS Full HD |
| Power | Official Raspberry Pi 5A USB-C PSU |
| Storage | Pimoroni NVMe Base + Samsung 980 500GB |
| UPS | Geekworm X734 |
| Enclosure | 3D-printed custom frame or VESA mount |

### Large Wall Calendar Build (~$550–700 total)
| Component | Choice |
|---|---|
| SBC | Raspberry Pi 5 (4GB) |
| Display | Waveshare 21.5" Capacitive Touch Monitor |
| Power | Official Raspberry Pi 5A USB-C PSU + display PSU |
| Storage | Samsung T7 USB SSD 500GB |
| UPS | PiSugar S3 |
| Enclosure | VESA wall mount bracket |

### Large Display + Overlay Build (~$400–550 total)
| Component | Choice |
|---|---|
| SBC | Raspberry Pi 5 (4GB) |
| Display | Any 21"–24" IPS LCD monitor (buy used or budget) |
| Touch | USB IR Touch Frame Overlay sized to match your monitor |
| Power | Official Raspberry Pi 5A USB-C PSU |
| Storage | Samsung PRO Endurance 128GB microSD |
| UPS | PiSugar S3 |
| Enclosure | VESA wall mount — monitor + Pi bracket |
