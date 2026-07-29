# Copyright (c) 2020 SUSE Software Solutions Germany GmbH.  All rights reserved.
#
# This file is part of kiwi-boxed-build.
#
# kiwi-boxed-build is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# kiwi-boxed-build is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with kiwi-boxed-build.  If not, see <http://www.gnu.org/licenses/>
#
import os
import platform
import logging
import struct
import ctypes
from typing import NamedTuple
from kiwi_boxed_plugin.utils.dir_files import DirFiles
from kiwi_boxed_plugin.utils.fetch_files import FetchFiles
from kiwi.command import Command
from kiwi.utils.checksum import Checksum
from kiwi.solver.repository import SolverRepository
from kiwi.system.uri import Uri
from kiwi.path import Path

from kiwi_boxed_plugin.box_config import BoxConfig
from kiwi_boxed_plugin.defaults import Defaults
from kiwi_boxed_plugin.exceptions import (
    KiwiBoxPluginChecksumError
)

vm_setup_type = NamedTuple(
    'vm_setup_type', [
        ('system', str),
        ('kernel', str),
        ('initrd', str),
        ('append', str),
        ('console', str),
        ('ram', str),
        ('smp', str)
    ]
)

log = logging.getLogger('kiwi')


class BoxDownload:
    """
    **Implements download of box file(s)**

    Reads the box configuration file and provides an interface
    to download the box files according to the configuration

    :param string boxname: name of the box from kiwi_boxed_plugin.yml
    :param string arch: arch name for box
    """
    def __init__(self, boxname: str, arch: str = '') -> None:
        self.arch = arch or platform.machine()
        self.box_config = BoxConfig(boxname, arch)
        self.box_dir = os.sep.join(
            [Defaults.get_local_box_cache_dir(), boxname]
        )
        self.box_stage = DirFiles(self.box_dir)
        self.system = ''
        self.kernel = ''
        self.initrd = ''
        Path.create(self.box_dir)

    def fetch_container(self) -> str:
        """
        Download container box from the open build service
        """
        container_source = self.box_config.get_box_container()
        if container_source:
            container_pull = [
                'sudo', 'podman', 'pull', container_source
            ]
            os.system(
                ' '.join(container_pull)
            )
        return container_source

    def fetch(
        self, update_check: bool = True, snapshot: bool = True
    ) -> vm_setup_type:
        """
        Download box from the open build service

        :param bool update_check: check for box updates True|False
        """
        fetcher = FetchFiles()
        download = update_check
        repo_source = self.box_config.get_box_source()
        if repo_source:
            repo = SolverRepository.new(
                Uri(repo_source, 'rpm-md')
            )
            packages_file = self.box_config.get_box_packages_file()
            packages_shasum_file = \
                self.box_config.get_box_packages_shasum_file()
            if update_check and packages_file and packages_shasum_file:
                local_packages_file = os.sep.join(
                    [self.box_dir, packages_file]
                )
                local_packages_shasum_file = os.sep.join(
                    [self.box_dir, packages_shasum_file]
                )
                local_packages_file_tmp = self.box_stage.register(
                    local_packages_file
                )
                local_packages_shasum_file_tmp = self.box_stage.register(
                    local_packages_shasum_file
                )
                repo.download_from_repository(
                    packages_file, local_packages_file_tmp
                )
                checksum = Checksum(local_packages_file_tmp)
                shasum = checksum.sha256()
                if checksum.matches(shasum, local_packages_shasum_file):
                    download = False
                    self.box_stage.deregister(local_packages_shasum_file)
                else:
                    self._create_packages_checksum(
                        local_packages_shasum_file_tmp, shasum
                    )

            for box_file in self.box_config.get_box_files():
                local_box_file = os.sep.join([self.box_dir, box_file])
                if not os.path.exists(local_box_file):
                    download = True
                if download:
                    log.info('Downloading {0}'.format(box_file))
                    local_box_file_tmp = self.box_stage.register(
                        local_box_file
                    )
                    box_file_link = os.sep.join(
                        [repo._get_mime_typed_uri(), box_file]
                    )
                    fetcher.wget(
                        url=box_file_link, filename=local_box_file_tmp
                    )

            if download:
                self.box_stage.commit()

            for box_file in self.box_config.get_box_files():
                local_box_file = os.sep.join([self.box_dir, box_file])
                if box_file.endswith('.qcow2'):
                    if update_check and snapshot and not self._checksum_ok(
                        local_box_file
                    ):
                        raise KiwiBoxPluginChecksumError(
                            'Checksum failed for {local_box_file}'
                        )
                    self.system = local_box_file
                if box_file.endswith('.tar.xz'):
                    if update_check and not self._checksum_ok(local_box_file):
                        raise KiwiBoxPluginChecksumError(
                            'Checksum failed for {local_box_file}'
                        )
                    self.kernel = self._extract_kernel_from_tarball(
                        local_box_file
                    )
                    if self.box_config.use_initrd():
                        self.initrd = self._extract_initrd_from_tarball(
                            local_box_file
                        )

        return vm_setup_type(
            system=self.system,
            kernel=self.kernel,
            initrd=self.initrd,
            append='console={0} {1}'.format(
                self.box_config.get_box_console(),
                self.box_config.get_box_kernel_cmdline()
            ),
            console=self.box_config.get_box_console(),
            ram=self.box_config.get_box_memory_mbytes(),
            smp=self.box_config.get_box_processors()
        )

    def _checksum_ok(self, filename: str) -> bool:
        checksum = Checksum(filename)
        shasum = checksum.sha256()
        sumfile = f'{filename}.sha256'
        log.info(
            'Checksum test {} -> {}'.format(filename, sumfile)
        )
        return checksum.matches(shasum, sumfile)

    def _create_packages_checksum(self, filename: str, shasum: str):
        with open(filename, 'w') as sha_file:
            sha_file.write(shasum)

    def _extract_kernel_from_tarball(self, tarfile: str) -> str:
        Command.run(
            [
                'tar', '-C', self.box_dir,
                '--transform', f's/.*/kernel.{self.arch}/',
                '--wildcards', '-xf', tarfile, '*.kernel'
            ]
        )
        kernel_file = os.sep.join([self.box_dir, f'kernel.{self.arch}'])
        self._unpack_zboot_if_needed(kernel_file)
        return kernel_file

    def _unpack_zboot_if_needed(self, kernel_path: str) -> None:
        if not os.path.isfile(kernel_path):
            return
        try:
            with open(kernel_path, 'rb') as f:
                data = f.read()
            if data[:2] == b'MZ' and b'zimg' in data[:32]:
                start_off = struct.unpack('<I', data[8:12])[0]
                payload_size = struct.unpack('<I', data[12:16])[0]
                comp_type = data[24:32].rstrip(b'\x00')
                decomp = None
                if comp_type == b'zstd':
                    payload = data[start_off:start_off + payload_size]
                    libzstd = ctypes.CDLL('libzstd.so.1')
                    libzstd.ZSTD_decompress.argtypes = [
                        ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t
                    ]
                    libzstd.ZSTD_decompress.restype = ctypes.c_size_t
                    libzstd.ZSTD_isError.argtypes = [ctypes.c_size_t]
                    libzstd.ZSTD_isError.restype = ctypes.c_uint
                    out_capacity = 256 * 1024 * 1024
                    out_buf = ctypes.create_string_buffer(out_capacity)
                    res = libzstd.ZSTD_decompress(out_buf, out_capacity, payload, len(payload))
                    if not libzstd.ZSTD_isError(res):
                        decomp = out_buf.raw[:res]
                elif comp_type in (b'gzip', b'gz'):
                    import gzip
                    decomp = gzip.decompress(data[start_off:start_off + payload_size])
                elif comp_type in (b'xz', b'lzma'):
                    import lzma
                    decomp = lzma.decompress(data[start_off:start_off + payload_size])
                elif comp_type in (b'bz2', b'bzip2'):
                    import bz2
                    decomp = bz2.decompress(data[start_off:start_off + payload_size])

                if decomp:
                    log.info(
                        f'Unpacked EFI zboot payload ({comp_type.decode("ascii", "ignore")}) in {kernel_path}'
                    )
                    with open(kernel_path, 'wb') as out_f:
                        out_f.write(decomp)
        except Exception as issue:
            log.warning(f'Failed to unpack EFI zboot kernel: {issue}')

    def _extract_initrd_from_tarball(self, tarfile: str) -> str:
        Command.run(
            [
                'tar', '-C', self.box_dir,
                '--transform', f's/.*/initrd.{self.arch}/',
                '--wildcards', '-xf', tarfile, '*.initrd'
            ]
        )
        return os.sep.join([self.box_dir, f'initrd.{self.arch}'])
