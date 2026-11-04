// Connector names, mode and placement match the reviewed Zenbook candidate.
// A packaged native engine with the matching white-point ABI is required;
// these values are not physical panel qualification on their own.
export const output = {
  profiles: [
    {
      name: "zenbook-two-panels",
      displays: [
        {
          display: "eDP-1",
          mode: [2880, 1800],
          position: [0, 0],
          scale: 2,
          color_temperature: 3850,
        },
        {
          display: "eDP-2",
          mode: [2880, 1800],
          position: [0, 900],
          scale: 2,
          color_temperature: 3350,
        },
      ],
    },
  ],
};
