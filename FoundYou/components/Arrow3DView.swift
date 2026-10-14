import SwiftUI
import RealityKit
import UIKit
import simd

struct Arrow3DView: View {

    let orientation: simd_quatd
    var targetBearing: Double = 0

    var body: some View {
        RealityView { content in
            let arrow = makeArrow()

            arrow.name = "FoundYouArrow"
            arrow.position = [0, 0, -1.2]
            arrow.scale = SIMD3<Float>(repeating: 2.5)

            content.add(arrow)

        } update: { content in

            guard let arrow = content.entities.first(
                where: { $0.name == "FoundYouArrow" }
            ) else {
                return
            }

            // Core Motion .xTrueNorthZVertical:
            // +X = Kuzey
            // +Y = Batı
            // +Z = Yukarı

            let radians = targetBearing * .pi / 180

            // Bearing saat yönünde artar:
            // 0° = Kuzey, 90° = Doğu
            let targetWorld = SIMD3<Double>(
                cos(radians),
                -sin(radians),
                0
            )

            // Dünya yönünü telefon koordinatlarına dönüştür.
            let targetDevice = orientation.inverse.act(targetWorld)

            let direction = SIMD3<Float>(
                Float(targetDevice.x),
                Float(targetDevice.y),
                Float(targetDevice.z)
            )

            guard simd_length_squared(direction) > 0.000001 else {
                return
            }

            let target = simd_normalize(direction)

            // Okun geometrik ucu +Y yönüne bakıyor.
            let arrowForward = SIMD3<Float>(0, 1, 0)

            arrow.orientation = simd_quatf(
                from: arrowForward,
                to: target
            )
        }
    }

    private func makeArrow() -> ModelEntity {

        let points: [SIMD2<Float>] = [
            [0, 0.55],
            [-0.32, 0.10],
            [-0.13, 0.10],
            [-0.13, -0.55],
            [0.13, -0.55],
            [0.13, 0.10],
            [0.32, 0.10]
        ]

        let depth: Float = 0.08

        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for z in [depth / 2, -depth / 2] {
            for p in points {
                vertices.append([p.x, p.y, z])
            }
        }

        let triangles: [UInt32] = [
            0, 1, 2,
            0, 2, 5,
            0, 5, 6,
            2, 3, 4,
            2, 4, 5
        ]

        indices.append(contentsOf: triangles)

        for i in stride(from: 0, to: triangles.count, by: 3) {
            indices.append(contentsOf: [
                triangles[i + 2] + 7,
                triangles[i + 1] + 7,
                triangles[i] + 7
            ])
        }

        for i in 0..<points.count {
            let next = (i + 1) % points.count

            let a = UInt32(i)
            let b = UInt32(next)
            let c = UInt32(next + points.count)
            let d = UInt32(i + points.count)

            indices.append(contentsOf: [
                a, b, c,
                a, c, d
            ])
        }

        var descriptor = MeshDescriptor(name: "FoundYouArrow")
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .triangles(indices)

        do {
            let mesh = try MeshResource.generate(from: [descriptor])

            // Işıktan etkilenmeyen turkuaz
            let material = UnlitMaterial(
                color: UIColor(
                    red: 0.0,
                    green: 0.9,
                    blue: 1.0,
                    alpha: 1.0
                )
            )

            return ModelEntity(
                mesh: mesh,
                materials: [material]
            )

        } catch {
            print("Arrow mesh error:", error)
            return ModelEntity()
        }
    }
}

#Preview {
    Arrow3DView(
        orientation: simd_quatd(
            ix: 0,
            iy: 0,
            iz: 0,
            r: 1
        ),
        targetBearing: 90
    )
}
