FROM python:3.8-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    eventlet==0.30.2 \
    oslo.config \
    oslo.log

RUN git clone --depth 1 https://github.com/faucetsdn/ryu.git /ryu && \
    pip install /ryu && \
    rm -rf /ryu/.git

EXPOSE 6633 8080

CMD ["ryu-manager", \
     "--observe-links", \
     "ryu.app.simple_switch_13", \
     "ryu.app.ofctl_rest", \
     "ryu.app.gui_topology.gui_topology"]
