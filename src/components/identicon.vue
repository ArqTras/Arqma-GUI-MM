<template>
  <div
    class="identicon"
    :style="{
      backgroundImage: 'url(' + img + ')',
      width: 8 * size + 'px',
      height: 8 * size + 'px',
    }"
  >
    <q-menu
      v-if="menu"
      context-menu
    >
      <q-list
        separator
        class="context menu"
      >
        <q-item
          v-close-popup
          clickable
          :disabled="img == defaultImg"
          @click="saveIdenticon()"
        >
          <q-item-section> Save identicon to file </q-item-section>
        </q-item>
      </q-list>
    </q-menu>
  </div>
</template>

<script>
import { computed, defineComponent, onMounted, ref, watch, toRefs } from "vue"
export default defineComponent({
  name: "Identicon",
  props: {
    address: {
      default: "",
      type: String
    },
    size: {
      type: Number,
      default: 5
    },
    menu: {
      type: Boolean,
      default: false
    }
  },
  setup (props) {
    const { address, size, menu } = toRefs(props)
    const randseed = ref(new Array(4))
    const img = ref("")
    const defaultImg = ref("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH4gkHECkpHU3uFgAAAZlJREFUWMPt2D1PwkAYB/D/AxWIbZUCAvGNwZiAcTG+JQ4sJn4AV7+UfgNXjY6ObrppXBiEGBMUgimKKHDy2jpUUHGTIhe5Z7rc8OTX9p67e0oXu3cmOA4HOA8BFEABFMBhB0q9JnBrEgIxGeqsGx7fCBwSoVExUMpUoV+VwPTG4ICRLQ2BmPJj3qU44Y/K8EdlpE8LeExUBgPU5kZhGiaYXkfmrIhytg6SgMn1cYSWVRARIps+ML3+6zfZE5Dl60gd5b/NmU0ge/6CQpJhYScMAPBFZTC9+PdF0o37GtViE6ZhXZQ8Xom/KiYCQNa4+WbwB5yOe0FkCQspxhcwtKJiYtGq7ucbhtd0dXD7YHeEV1VMbXgBAOVcDbcnT/ycJMElpYOrPNSQPNR5OupMzMS1zvZzfaDbktU2YHht7HP7OdZte2zbgHLI3Rm3aiZ/QHJ+fGjD3i7WNqDTZaUiB/F13WqHHRXbV6BHk0BOAhHA8g3+gPPbQbgUayFe7t3ztwbNVn9+8fz/nqQdif2caDsFUAAFUACHEfgOXvt3FLbL3AsAAAAASUVORK5CYII=")

    // Computed props
    const isDefault = computed(() => {
      return img.value === defaultImg.value
    })

    // Watchers
    const addressWatcher = watch(address, async (newVal, oldVal) => {
      try {
        if (newVal && isAddressValid(newVal)) {
          createIcon({
            seed: address,
            scale: size.value
          })
        } else {
          img.value = defaultImg.value
        }
      } catch (error) {
        await api.error("components/identicon", "addressWatcher", error.stack || error)
      }
    })

    onMounted(() => {
      if (address.value && isAddressValid(address.value)) {
        createIcon({
          seed: address.value,
          scale: 12
        })
      } else {
        img.value = defaultImg.value
      }
    })

    // Methods
    const saveIdenticon = async () => {
      try {
        if (img.value === defaultImg.value) {
          return
        }
        api.send("core", "save_png", {
          img: img.value,
          type: "Identicon"
        })
      } catch (error) {
        await api.error("components/identicon", "addressWatcher", error.stack || error)
      }
    }

    const isAddressValid = async (input) => {
      try {
        if (!/^[0-9A-Za-z]+$/.test(input)) return false

        switch (input.substring(0, 4)) {
          case "Sumo":
          case "RYoL":
          case "Suto":
          case "RYoT":
            return input.length === 99

          case "Subo":
          case "Suso":
            return input.length === 98

          case "RYoS":
          case "RYoU":
            return input.length === 99

          case "Sumi":
          case "RYoN":
          case "Suti":
          case "RYoE":
            return input.length === 110

          case "RYoK":
          case "RYoH":
            return input.length === 55

          default:
            return false
        }
      } catch (error) {
        await api.error("components/identicon", "isAddressValid", error.stack || error)
      }
    }

    const seedrand = async (seed) => {
      try {
        for (let i = 0; i < randseed.value.length; i++) {
          randseed.value[i] = 0
        }
        for (let b = 0; b < seed.length; b++) {
          randseed.value[b % 4] =
                (randseed.value[b % 4] << 5) -
                randseed.value[b % 4] +
                seed.charCodeAt(b)
        }
      } catch (error) {
        await api.error("components/identicon", "seedrand", error.stack || error)
      }
    }

    const rand = async () => {
      try {
        // based on Java's String.hashCode(), expanded to 4 32bit values
        const t = randseed.value[0] ^ (randseed.value[0] << 11)

        randseed.value[0] = randseed.value[1]
        randseed.value[1] = randseed.value[2]
        randseed.value[2] = randseed.value[3]
        randseed.value[3] = randseed.value[3] ^ (randseed.value[3] >> 19) ^ t ^ (t >> 8)

        return (randseed.value[3] >>> 0) / ((1 << 31) >>> 0)
      } catch (error) {
        await api.error("components/identicon", "rand", error.stack || error)
      }
    }

    const createColor = async () => {
      try {
        // saturation is the whole color spectrum
        const h = Math.floor(rand() * 360)
        // saturation goes from 40 to 100, it avoids greyish colors
        const s = rand() * 60 + 40 + "%"
        // lightness can be anything from 0 to 100, but probabilities are a bell curve around 50%
        const l =
              (rand() + rand() + rand() + rand()) * 25 + "%"

        const color = "hsl(" + h + "," + s + "," + l + ")"
        return color
      } catch (error) {
        await api.error("components/identicon", "createColor", error.stack || error)
      }
    }

    const createImageData = async (size) => {
      try {
        const width = size // Only support square icons for now
        const height = size

        const dataWidth = Math.ceil(width / 2)
        const mirrorWidth = width - dataWidth

        const data = []
        for (let y = 0; y < height; y++) {
          let row = []
          for (let x = 0; x < dataWidth; x++) {
            // this makes foreground and background color to have a 43% (1/2.3) probability
            // spot color has 13% chance
            row[x] = Math.floor(rand() * 2.3)
          }
          const r = row.slice(0, mirrorWidth)
          r.reverse()
          row = row.concat(r)

          for (let i = 0; i < row.length; i++) {
            data.push(row[i])
          }
        }
        return data
      } catch (error) {
        await api.error("components/identicon", "createImageData", error.stack || error)
      }
    }

    const buildOpts = async (opts) => {
      try {
        const newOpts = {}

        newOpts.seed =
              opts.seed || Math.floor(Math.random() * Math.pow(10, 16)).toString(16)

        seedrand.value(newOpts.seed)

        newOpts.size = opts.size || 8
        newOpts.scale = opts.scale || 4
        newOpts.color = opts.color || createColor()
        newOpts.bgcolor = opts.bgcolor || createColor()
        newOpts.spotcolor = opts.spotcolor || createColor()

        return newOpts
      } catch (error) {
        await api.error("components/identicon", "buildOpts", error.stack || error)
      }
    }

    const renderIcon = async (opts, canvas) => {
      try {
        opts = buildOpts(opts || {})
        const imageData = createImageData(opts.size)
        const width = Math.sqrt(imageData.length)

        canvas.width = canvas.height = opts.size * opts.scale

        const cc = canvas.getContext("2d")
        cc.fillStyle = opts.bgcolor
        cc.fillRect(0, 0, canvas.width, canvas.height)
        cc.fillStyle = opts.color

        for (let i = 0; i < imageData.length; i++) {
          // if data is 0, leave the background
          if (imageData[i]) {
            const row = Math.floor(i / width)
            const col = i % width

            // if data is 2, choose spot color, if 1 choose foreground
            cc.fillStyle = imageData[i] === 1 ? opts.color : opts.spotcolor

            cc.fillRect(
              col * opts.scale,
              row * opts.scale,
              opts.scale,
              opts.scale
            )
          }
        }
        return canvas
      } catch (error) {
        await api.error("components/identicon", "renderIcon", error.stack || error)
      }
    }

    const createIcon = async (opts) => {
      try {
        const canvas = document.createElement("canvas")
        renderIcon(opts, canvas)
        img.value = canvas.toDataURL()
      } catch (error) {
        await api.error("components/identicon", "createIcon", error.stack || error)
      }
    }

    return {
      randseed,
      img,
      defaultImg,
      isDefault,
      addressWatcher,
      saveIdenticon,
      isAddressValid,
      seedrand,
      rand,
      createColor,
      createImageData,
      buildOpts,
      renderIcon,
      createIcon
    }
  }
})
</script>

<style></style>
