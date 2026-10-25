local unlocker, mint, addon = ...

addon.warrior.settings["generic"] = {
    strategy = {
        name = "Strategy",
        type = "Dropdown",
        options = {"Auto", "Single Target", "AoE"},
        default = 1
    },
    autoCharge = {
        name = "Auto Charge",
        type = "Checkbox",
        default = true
    }
}
