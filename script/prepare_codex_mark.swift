import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("usage: swift prepare_codex_mark.swift <input> <output>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("could not read input image\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
) else { exit(1) }
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

func isBackground(_ pixel: Int) -> Bool {
    let offset = pixel * 4
    let red = Int(pixels[offset])
    let green = Int(pixels[offset + 1])
    let blue = Int(pixels[offset + 2])
    return min(red, green, blue) > 226 && max(red, green, blue) - min(red, green, blue) < 20
}

var visited = [Bool](repeating: false, count: width * height)
var queue: [Int] = []
queue.reserveCapacity(width * height / 2)

func enqueue(_ x: Int, _ y: Int) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let pixel = y * width + x
    guard !visited[pixel], isBackground(pixel) else { return }
    visited[pixel] = true
    queue.append(pixel)
}

for x in 0..<width {
    enqueue(x, 0)
    enqueue(x, height - 1)
}
for y in 0..<height {
    enqueue(0, y)
    enqueue(width - 1, y)
}

var cursor = 0
while cursor < queue.count {
    let pixel = queue[cursor]
    cursor += 1
    let x = pixel % width
    let y = pixel / width
    enqueue(x - 1, y)
    enqueue(x + 1, y)
    enqueue(x, y - 1)
    enqueue(x, y + 1)
}

for pixel in queue {
    let offset = pixel * 4
    pixels[offset] = 0
    pixels[offset + 1] = 0
    pixels[offset + 2] = 0
    pixels[offset + 3] = 0
}

var minX = width
var minY = height
var maxX = 0
var maxY = 0
for y in 0..<height {
    for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}

guard let processed = context.makeImage() else { exit(1) }
let padding = 18
let crop = CGRect(
    x: max(minX - padding, 0),
    y: max(minY - padding, 0),
    width: min(maxX + padding, width - 1) - max(minX - padding, 0) + 1,
    height: min(maxY + padding, height - 1) - max(minY - padding, 0) + 1
)
guard let cropped = processed.cropping(to: crop),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(destination, cropped, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
